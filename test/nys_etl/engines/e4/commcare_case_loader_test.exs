defmodule NYSETL.Engines.E4.CommcareCaseLoaderTest do
  use NYSETL.DataCase, async: true
  use Oban.Testing, repo: NYSETL.Repo

  import NYSETL.Test.TestHelpers
  import ExUnit.CaptureLog
  import Mox

  alias NYSETL.Commcare
  alias NYSETL.ECLRS
  alias NYSETL.Engines.E4.CommcareCaseLoader
  alias NYSETL.Test

  setup [:verify_on_exit!, :start_supervised_oban]

  def event_data(schema, name) do
    schema
    |> Repo.preload(:events)
    |> Map.get(:events)
    |> Enum.find(fn e -> e.type == name end)
    |> Map.get(:data)
  end

  test "is unique across case_id and county_id" do
    county_1_fips = Test.Fixtures.test_county_1_fips()
    county_2_fips = Test.Fixtures.test_county_2_fips()

    Enum.each(["abc", "def", "abc", "def"], fn case_id ->
      Enum.each([county_1_fips, county_2_fips], fn county_id ->
        %{"case_id" => case_id, "county_id" => county_id}
        |> CommcareCaseLoader.new()
        |> Oban.insert!()
      end)
    end)

    assert [
             %Oban.Job{args: %{"case_id" => "def", "county_id" => county_2_fips}},
             %Oban.Job{args: %{"case_id" => "def", "county_id" => county_1_fips}},
             %Oban.Job{args: %{"case_id" => "abc", "county_id" => county_2_fips}},
             %Oban.Job{args: %{"case_id" => "abc", "county_id" => county_1_fips}}
           ] = all_enqueued(worker: CommcareCaseLoader)
  end

  describe "perform" do
    test "checks commcare for the case, and when it is not in commcare yet, XML built from just eclrs data is POSTed to CommCare" do
      case_id = "case-id-abcd1234"
      {:ok, county} = ECLRS.find_or_create_county(Test.Fixtures.test_county_1_fips())
      {:ok, person} = %{data: %{}, patient_keys: ["123"]} |> Test.Factory.person() |> Commcare.create_person()

      {:ok, index_case} =
        %{case_id: case_id, data: %{full_name: "Original Full Name"}, person_id: person.id, county_id: county.id}
        |> Commcare.create_index_case()

      NYSETL.HTTPoisonMock
      |> expect(:get, fn url, _headers, _opts ->
        assert url =~ "/a/uk-midsomer-cdcms/api/v0.5/case/case-id-abcd1234/"
        {:ok, %{status_code: 404, body: ""}}
      end)
      |> expect(:post, fn url, xml, _headers ->
        doc = xml |> Floki.parse_document!()
        assert url =~ "/a/uk-midsomer-cdcms/receiver/"
        assert Test.Xml.attr(doc, "case:nth-of-type(1)", "case_id") == case_id
        assert Test.Xml.text(doc, "case:nth-of-type(1) update full_name") == "Original Full Name"
        {:ok, %{status_code: 201, body: Test.Fixtures.commcare_submit_response(:success)}}
      end)

      worker_result = CommcareCaseLoader.perform(%{attempt: 1, args: %{"case_id" => case_id, "county_id" => Test.Fixtures.test_county_1_fips()}})
      assert worker_result == :ok

      index_case |> assert_events(["send_to_commcare_succeeded"])
    end

    """
    checks commcare for the case, and when it is present in CommCare,
    it builds XML from a merge of the ECLRS data and CommCare data
    and POSTs it to CommCare
    """
    |> test do
      case_id = "case-id-abcd1234"
      {:ok, county} = ECLRS.find_or_create_county(Test.Fixtures.test_county_1_fips())
      {:ok, person} = %{data: %{}, patient_keys: ["123"]} |> Test.Factory.person() |> Commcare.create_person()

      {:ok, index_case} =
        %{case_id: case_id, data: %{full_name: "Original Full Name"}, person_id: person.id, county_id: county.id}
        |> Commcare.create_index_case()

      me = self()

      NYSETL.HTTPoisonMock
      |> expect(:get, fn url, _headers, _opts ->
        assert url =~ "/a/uk-midsomer-cdcms/api/v0.5/case/case-id-abcd1234/"

        {:ok,
         %{
           status_code: 200,
           body:
             %{
               "case_id" => case_id,
               "properties" => %{
                 "full_name" => "Updated Full Name",
                 "owner_id" => Test.Fixtures.test_county_1_location_id()
               }
             }
             |> Jason.encode!()
         }}
      end)
      |> expect(:post, fn url, xml, _headers ->
        send(me, {:xml, xml})
        doc = xml |> Floki.parse_document!()
        assert url =~ "/a/uk-midsomer-cdcms/receiver/"
        assert Test.Xml.attr(doc, "case:nth-of-type(1)", "case_id") == case_id
        assert Test.Xml.text(doc, "case:nth-of-type(1) update full_name") == "Updated Full Name"
        {:ok, %{status_code: 201, body: Test.Fixtures.commcare_submit_response(:success)}}
      end)

      worker_result = CommcareCaseLoader.perform(%{attempt: 1, args: %{"case_id" => case_id, "county_id" => Test.Fixtures.test_county_1_fips()}})
      assert worker_result == :ok

      receive do
        {:xml, xml} ->
          %Commcare.IndexCase{events: [updated_from_commcare, update_event]} = Repo.preload(index_case, :events)

          assert %{type: "updated_from_commcare"} = updated_from_commcare

          assert Euclid.Term.present?(update_event.data["response"])
          assert Euclid.Term.present?(update_event.data["timestamp"])
          assert update_event.data["action"] == "update"
          assert update_event.stash == xml
      after
        250 ->
          flunk("Never got the XML to assert against")
      end

      {:ok, reloaded_index_case} = Commcare.get_index_case(case_id: case_id, county_id: county.id)
      assert reloaded_index_case.data["full_name"] == "Updated Full Name"

      reloaded_index_case |> assert_events(["updated_from_commcare", "send_to_commcare_succeeded"])
    end

    test "sends a new patient case with new lab result cases to CommCare" do
      earlier = ~U[2020-06-01 00:00:00Z]
      later = ~U[2020-06-02 00:00:00Z]

      {:ok, county} = ECLRS.find_or_create_county(Test.Fixtures.test_county_1_fips())
      {:ok, person} = %{data: %{}, patient_keys: ["123"]} |> Test.Factory.person() |> Commcare.create_person()
      {:ok, index_case} = %{data: %{full_name: "Max Headroom"}, person_id: person.id, county_id: county.id} |> Commcare.create_index_case()

      {:ok, earliest_lab_result} =
        %{data: %{tid: "earliest"}, inserted_at: earlier, index_case_id: index_case.id, accession_number: "lab_result_1_accession_number"}
        |> Commcare.create_lab_result()

      {:ok, latest_lab_result} =
        %{data: %{tid: "latest"}, inserted_at: later, index_case_id: index_case.id, accession_number: "lab_result_2_accession_number"}
        |> Commcare.create_lab_result()

      me = self()

      NYSETL.HTTPoisonMock
      |> expect(:get, fn url, _headers, _opts ->
        assert url =~ "/a/uk-midsomer-cdcms/api/v0.5/case/" <> index_case.case_id
        {:ok, %{status_code: 404, body: ""}}
      end)
      |> expect(:post, fn url, xml, _headers ->
        send(me, {:xml, xml})
        doc = xml |> Floki.parse_document!()

        assert url =~ "/a/uk-midsomer-cdcms/receiver/"

        assert Test.Xml.text(doc, "case:nth-of-type(1) update full_name") == "Max Headroom"
        assert Test.Xml.attr(doc, "case:nth-of-type(1)", "case_id") == index_case.case_id
        assert Test.Xml.text(doc, "case:nth-of-type(1) create owner_id") == "a1a1a1a1a1"

        assert Test.Xml.attr(doc, "case:nth-of-type(2)", "case_id") == earliest_lab_result.case_id
        assert Test.Xml.text(doc, "case:nth-of-type(2) create case_type") == "lab_result"
        assert Test.Xml.text(doc, "case:nth-of-type(2) update accession_number") == "lab_result_1_accession_number"

        assert Test.Xml.attr(doc, "case:nth-of-type(3)", "case_id") == latest_lab_result.case_id
        assert Test.Xml.text(doc, "case:nth-of-type(3) create case_type") == "lab_result"
        assert Test.Xml.text(doc, "case:nth-of-type(3) create owner_id") == "-"
        assert Test.Xml.text(doc, "case:nth-of-type(3) update owner_id") == "-"
        assert Test.Xml.text(doc, "case:nth-of-type(3) update accession_number") == "lab_result_2_accession_number"

        {:ok, %{status_code: 201, body: Test.Fixtures.commcare_submit_response(:success)}}
      end)

      worker_result = CommcareCaseLoader.perform(%{attempt: 1, args: %{"case_id" => index_case.case_id, "county_id" => county.id}})
      assert worker_result == :ok

      receive do
        {:xml, xml} ->
          %Commcare.IndexCase{events: [event]} = Repo.preload(index_case, :events)

          assert Euclid.Term.present?(event.data["response"])
          assert Euclid.Term.present?(event.data["timestamp"])
          assert event.data["action"] == "create"
          assert event.stash == xml
      after
        250 ->
          flunk("Never got the XML to assert against")
      end

      index_case |> assert_events(["send_to_commcare_succeeded"])
    end

    test "when there is an error trying to get the case from commcare, the job fails (to be retried later) and logs" do
      {:ok, county} = ECLRS.find_or_create_county(Test.Fixtures.test_county_1_fips())
      {:ok, person} = %{data: %{}, patient_keys: ["123"]} |> Test.Factory.person() |> Commcare.create_person()
      {:ok, index_case} = %{data: %{"full_name" => "Original Full Name"}, person_id: person.id, county_id: county.id} |> Commcare.create_index_case()

      NYSETL.HTTPoisonMock
      |> expect(:get, fn _url, _headers, _opts ->
        {:error, %{body: "Error!", status_code: 501, request_url: "http://example.com"}}
      end)
      |> expect(:post, 0, fn _url, _body, _headers -> :ok end)

      assert capture_log(fn ->
               worker_result = CommcareCaseLoader.perform(%{attempt: 1, args: %{"case_id" => index_case.case_id, "county_id" => county.id}})
               assert worker_result == {:error, "Error!"}
             end) =~ "Error when trying to get <case_id:#{index_case.case_id} county_domain:uk-midsomer-cdcms county_id:1111>"

      {:ok, reloaded_index_case} = Commcare.get_index_case(case_id: index_case.case_id, county_id: county.id)
      assert reloaded_index_case == index_case

      reloaded_index_case |> assert_events([])
    end

    test "when commcare rate limits when getting the case, the job snoozes and logs" do
      {:ok, county} = ECLRS.find_or_create_county(Test.Fixtures.test_county_1_fips())
      {:ok, person} = %{data: %{}, patient_keys: ["123"]} |> Test.Factory.person() |> Commcare.create_person()
      {:ok, index_case} = %{data: %{"full_name" => "Original Full Name"}, person_id: person.id, county_id: county.id} |> Commcare.create_index_case()

      NYSETL.HTTPoisonMock
      |> expect(:get, fn _url, _headers, _opts ->
        {:ok, %{body: "Hold up there, buddy", status_code: 429, request_url: "http://example.com"}}
      end)
      |> expect(:post, 0, fn _url, _body, _headers -> :ok end)

      assert capture_log(fn ->
               worker_result = CommcareCaseLoader.perform(%{attempt: 1, args: %{"case_id" => index_case.case_id, "county_id" => county.id}})
               assert worker_result == {:snooze, 1}
             end) =~ "Error when trying to get <case_id:#{index_case.case_id} county_domain:uk-midsomer-cdcms county_id:1111>, reason=rate_limited"

      {:ok, reloaded_index_case} = Commcare.get_index_case(case_id: index_case.case_id, county_id: county.id)
      assert reloaded_index_case == index_case

      reloaded_index_case |> assert_events([])
    end

    test "when there is an HTTP error posting the case to commcare, the job fails (to be retried later)" do
      {:ok, county} = ECLRS.find_or_create_county(Test.Fixtures.test_county_1_fips())
      {:ok, person} = %{data: %{}, patient_keys: ["123"]} |> Test.Factory.person() |> Commcare.create_person()

      {:ok, index_case} =
        %{
          data: %{"full_name" => "Original Full Name", "owner_id" => Test.Fixtures.test_county_1_location_id()},
          person_id: person.id,
          county_id: county.id
        }
        |> Commcare.create_index_case()

      NYSETL.HTTPoisonMock
      |> expect(:get, fn url, _headers, _opts ->
        assert url =~ "/a/uk-midsomer-cdcms/api/v0.5/case/#{index_case.case_id}/"

        {:ok,
         %{
           status_code: 200,
           body:
             %{
               "case_id" => index_case.case_id,
               "properties" => %{"owner_id" => Test.Fixtures.test_county_1_location_id()}
             }
             |> Jason.encode!()
         }}
      end)
      |> expect(:post, fn _url, _body, _headers ->
        {:error, %{status_code: 500, body: "Error!"}}
      end)

      assert capture_log(fn ->
               worker_result = CommcareCaseLoader.perform(%{attempt: 1, args: %{"case_id" => index_case.case_id, "county_id" => county.id}})
               assert worker_result == {:error, "Error!"}
             end) =~ "recording case case_id=#{index_case.case_id} as failed to send to commcare"

      {:ok, reloaded_index_case} = Commcare.get_index_case(case_id: index_case.case_id, county_id: county.id)
      reloaded_index_case |> assert_events(["send_to_commcare_failed"])
    end

    test "when there is a generic error posting the case to commcare, the job fails (to be retried later)" do
      {:ok, county} = ECLRS.find_or_create_county(Test.Fixtures.test_county_1_fips())
      {:ok, person} = %{data: %{}, patient_keys: ["123"]} |> Test.Factory.person() |> Commcare.create_person()
      {:ok, index_case} = %{data: %{"full_name" => "Original Full Name"}, person_id: person.id, county_id: county.id} |> Commcare.create_index_case()

      NYSETL.HTTPoisonMock
      |> expect(:get, fn url, _headers, _opts ->
        assert url =~ "/a/uk-midsomer-cdcms/api/v0.5/case/#{index_case.case_id}/"

        {:ok,
         %{
           status_code: 200,
           body:
             %{
               "case_id" => index_case.case_id,
               "properties" => %{"full_name" => "Updated Full Name", "owner_id" => Test.Fixtures.test_county_1_location_id()}
             }
             |> Jason.encode!()
         }}
      end)
      |> expect(:post, fn _url, _body, _headers ->
        {:error, %{something: "went wrong"}}
      end)

      assert capture_log(fn ->
               worker_result = CommcareCaseLoader.perform(%{attempt: 1, args: %{"case_id" => index_case.case_id, "county_id" => county.id}})
               assert worker_result == {:error, %{something: "went wrong"}}
             end) =~ "recording case case_id=#{index_case.case_id} as failed to send to commcare"

      {:ok, reloaded_index_case} = Commcare.get_index_case(case_id: index_case.case_id, county_id: county.id)
      assert reloaded_index_case.data["full_name"] == "Updated Full Name"

      reloaded_index_case |> assert_events(["updated_from_commcare", "send_to_commcare_failed"])
    end

    """
    when the case was transferred to another county,
    it creates a new case in the database,
    logs the transfer,
    builds XML from a merge of the ECLRS data and CommCare data
    and POSTs it to CommCare
    """
    |> test do
      initial_case_id = "initial-case-id-123"
      destination_case_id = "destination-case-id-456"
      county_fips = Test.Fixtures.test_county_1_fips()
      county_domain = Test.Fixtures.test_county_1_domain()
      destination_county_fips = Test.Fixtures.test_county_2_fips()
      destination_county_domain = Test.Fixtures.test_county_2_domain()

      {:ok, county} = ECLRS.find_or_create_county(county_fips)
      {:ok, _destination_county} = ECLRS.find_or_create_county(destination_county_fips)
      {:ok, person} = %{data: %{"full_name" => "Original Full Name"}, patient_keys: ["123"]} |> Test.Factory.person() |> Commcare.create_person()

      {:ok, index_case} =
        %{
          case_id: initial_case_id,
          data: %{
            "phone_number" => "555-NEW-PHONE-FROM-ECLRS"
          },
          person_id: person.id,
          county_id: county.id
        }
        |> Commcare.create_index_case()

      initial_case_response = %{
        "case_id" => initial_case_id,
        "properties" => %{
          "owner_id" => Test.Fixtures.test_county_1_location_id(),
          "external_id" => "external-id-123",
          "transfer_destination_county_id" => destination_county_fips
        }
      }

      destination_case_response = %{
        "objects" => [
          %{
            "case_id" => destination_case_id,
            "properties" => %{
              "owner_id" => Test.Fixtures.test_county_2_location_id(),
              "external_id" => "external-id-123",
              "full_name" => "Full Name from CommCare",
              "address" => "Address from CommCare",
              "transfer_destination_county_id" => destination_county_fips,
              "transfer_source_case_id" => initial_case_id
            }
          }
        ]
      }

      NYSETL.HTTPoisonMock
      |> stub(:get, fn url, _headers, _opts ->
        cond do
          url =~ "/a/#{county_domain}/api/v0.5/case/#{initial_case_id}/" ->
            {:ok, %{status_code: 200, body: initial_case_response |> Jason.encode!()}}

          url =~ "/a/#{destination_county_domain}/api/v0.5/case/?external_id=external-id-123" ->
            {:ok, %{status_code: 200, body: destination_case_response |> Jason.encode!()}}

          true ->
            raise "url was not mocked: #{url}"
        end
      end)
      |> expect(:post, fn url, xml, _headers ->
        doc = xml |> Floki.parse_document!()
        assert url =~ "/a/#{destination_county_domain}/receiver/"
        assert Test.Xml.attr(doc, "case:nth-of-type(1)", "case_id") == destination_case_id
        assert Test.Xml.text(doc, "case:nth-of-type(1) update full_name") == "Full Name from CommCare"
        assert Test.Xml.text(doc, "case:nth-of-type(1) update address") == "Address from CommCare"
        assert Test.Xml.text(doc, "case:nth-of-type(1) update phone_number") == "555-NEW-PHONE-FROM-ECLRS"
        {:ok, %{status_code: 201, body: Test.Fixtures.commcare_submit_response(:success)}}
      end)

      :ok = CommcareCaseLoader.perform(%{attempt: 1, args: %{"case_id" => initial_case_id, "county_id" => county_fips}})

      {:ok, [reloaded_destination_index_case]} = Commcare.get_index_cases(person, county_id: destination_county_fips)
      assert reloaded_destination_index_case.case_id == destination_case_id
      assert reloaded_destination_index_case.data["full_name"] == "Full Name from CommCare"
      assert reloaded_destination_index_case.data["phone_number"] == "555-NEW-PHONE-FROM-ECLRS"
      assert reloaded_destination_index_case.data["address"] == "Address from CommCare"

      index_case |> assert_events(["send_to_commcare_rerouted"])
      reloaded_destination_index_case |> assert_events(["send_to_commcare_succeeded"])
    end

    test "Attaching a new test result to a case that has been transferred to a non-participating county" do
      # Important - this case is easy to confuse with the case where a test result comes into the system
      # annotated with a non-participating county (disregarding the case it belongs to). If the test result
      # comes in already annotated with a non-participating county, we ignore it (instead of sending to the
      # statewide county).
      initial_case_id = "initial-case-id-123"
      destination_case_id = "destination-case-id-456"
      county_fips = Test.Fixtures.test_county_1_fips()
      county_domain = Test.Fixtures.test_county_1_domain()
      county_location_id = Test.Fixtures.test_county_1_location_id()
      non_participating_county_fips = Test.Fixtures.nonparticipating_county_fips()

      statewide_county_location_id = Test.Fixtures.statewide_county_location_id()
      statewide_county_fips = Test.Fixtures.statewide_county_fips()
      statewide_county_domain = Test.Fixtures.statewide_county_domain()

      {:ok, county} = ECLRS.find_or_create_county(county_fips)
      {:ok, _statewide_county} = ECLRS.find_or_create_county(statewide_county_fips)

      {:ok, person} =
        %{
          data: %{
            "full_name" => "Original Full Name"
          },
          patient_keys: ["123"]
        }
        |> Test.Factory.person()
        |> Commcare.create_person()

      {:ok, index_case} =
        %{
          case_id: initial_case_id,
          data: %{
            "phone_number" => "555-NEW-PHONE-FROM-ECLRS"
          },
          person_id: person.id,
          county_id: county.id
        }
        |> Commcare.create_index_case()

      initial_case_response = %{
        "case_id" => initial_case_id,
        "properties" => %{
          "owner_id" => county_location_id,
          "external_id" => "external-id-123",
          "transfer_destination_county_id" => non_participating_county_fips,
          "transfer_destination_county_domain" => ""
        }
      }

      destination_case_response = %{
        "objects" => [
          %{
            "case_id" => destination_case_id,
            "properties" => %{
              "owner_id" => statewide_county_location_id,
              "external_id" => "external-id-123",
              "full_name" => "Full Name from CommCare",
              "address" => "Address from CommCare",
              "transfer_destination_county_id" => non_participating_county_fips,
              "transfer_destination_county_domain" => "",
              "transfer_source_case_id" => initial_case_id
            }
          }
        ]
      }

      NYSETL.HTTPoisonMock
      |> stub(
        :get,
        fn url, _headers, _opts ->
          cond do
            url =~ "/a/#{county_domain}/api/v0.5/case/#{initial_case_id}/" ->
              {:ok,
               %{
                 status_code: 200,
                 body: initial_case_response |> Jason.encode!()
               }}

            url =~ "/a/#{statewide_county_domain}/api/v0.5/case/?external_id=external-id-123" ->
              {:ok,
               %{
                 status_code: 200,
                 body:
                   destination_case_response
                   |> Jason.encode!()
               }}

            true ->
              raise "url was not mocked: #{url}"
          end
        end
      )
      |> expect(
        :post,
        fn url, request_body_xml, _headers ->
          request_body =
            request_body_xml
            |> Floki.parse_document!()

          assert url =~ "/a/#{statewide_county_domain}/receiver/"
          assert Test.Xml.attr(request_body, "case:nth-of-type(1)", "case_id") == destination_case_id
          {:ok, %{status_code: 201, body: Test.Fixtures.commcare_submit_response(:success)}}
        end
      )

      :ok =
        CommcareCaseLoader.perform(%{
          attempt: 1,
          args: %{
            "case_id" => initial_case_id,
            "county_id" => county_fips
          }
        })

      # Ensure that we have saved the information discovered in the county-transfer change.
      # We have created/updated the index_case with the new case details from the statewide domain.
      {:ok, [reloaded_destination_index_case]} = Commcare.get_index_cases(person, county_id: statewide_county_fips)
      assert reloaded_destination_index_case.case_id == destination_case_id

      index_case
      |> assert_events(["send_to_commcare_rerouted"])

      index_case
      |> event_data("send_to_commcare_rerouted")
      |> assert_eq(%{
        "reason" => "Update for this case sent to another case due to county transfer",
        "destination_case_id" => destination_case_id,
        "destination_county_id" => String.to_integer(statewide_county_fips),
        "destination_index_case_id" => reloaded_destination_index_case.id
      })

      reloaded_destination_index_case
      |> assert_events(["send_to_commcare_succeeded"])
    end

    """
    when the case was transferred to another county, and then the original case is updated again,
    the existing destination index case in our DB is updated, rather than a duplicate index case in our DB being created
    """
    |> test do
      initial_case_id = "initial-case-id-123"
      transferred_case_id = "transferred-case-id-456"
      county_fips = Test.Fixtures.test_county_1_fips()
      county_domain = Test.Fixtures.test_county_1_domain()
      destination_county_fips = Test.Fixtures.test_county_2_fips()
      destination_county_domain = Test.Fixtures.test_county_2_domain()

      {:ok, county} = ECLRS.find_or_create_county(county_fips)
      {:ok, _destination_county} = ECLRS.find_or_create_county(destination_county_fips)
      {:ok, person} = %{data: %{"full_name" => "Full Name from ECLRS"}, patient_keys: ["123"]} |> Test.Factory.person() |> Commcare.create_person()

      {:ok, initial_index_case} =
        %{case_id: initial_case_id, data: %{}, person_id: person.id, county_id: county.id}
        |> Commcare.create_index_case()

      {:ok, initial_lab_result} =
        %{data: %{tid: "initial"}, index_case_id: initial_index_case.id, accession_number: "lab_result_1_accession_number"}
        |> Commcare.create_lab_result()

      {:ok, transferred_index_case} =
        %{
          case_id: transferred_case_id,
          data: %{
            "full_name" => "Full Name from ECLRS",
            "phone_number" => "555-NEW-PHONE-FROM-ECLRS"
          },
          person_id: person.id,
          county_id: destination_county_fips
        }
        |> Commcare.create_index_case()

      {:ok, transferred_initial_lab_result} =
        %{data: %{tid: initial_lab_result.data.tid}, index_case_id: transferred_index_case.id, accession_number: initial_lab_result.accession_number}
        |> Commcare.create_lab_result()

      {:ok, initial_county_new_lab_result} =
        %{data: %{tid: "new"}, index_case_id: initial_index_case.id, accession_number: "lab_result_2_accession_number"}
        |> Commcare.create_lab_result()

      initial_case_response = %{
        "case_id" => initial_case_id,
        "properties" => %{
          "owner_id" => Test.Fixtures.test_county_1_location_id(),
          "external_id" => "external-id-123",
          "transfer_destination_county_id" => destination_county_fips
        }
      }

      destination_case_response = %{
        "objects" => [
          %{
            "case_id" => transferred_case_id,
            "properties" => %{
              "owner_id" => Test.Fixtures.test_county_2_location_id(),
              "external_id" => "external-id-123",
              "full_name" => "Full Name from CommCare",
              "address" => "Address from CommCare",
              "transfer_destination_county_id" => destination_county_fips,
              "transfer_source_case_id" => initial_case_id
            }
          }
        ]
      }

      NYSETL.HTTPoisonMock
      |> stub(:get, fn url, _headers, _opts ->
        cond do
          url =~ "/a/#{county_domain}/api/v0.5/case/#{initial_case_id}/" ->
            {:ok, %{status_code: 200, body: initial_case_response |> Jason.encode!()}}

          url =~ "/a/#{destination_county_domain}/api/v0.5/case/?external_id=external-id-123" ->
            {:ok, %{status_code: 200, body: destination_case_response |> Jason.encode!()}}

          true ->
            raise "url was not mocked: #{url}"
        end
      end)
      |> expect(:post, fn url, xml, _headers ->
        doc = xml |> Floki.parse_document!()
        assert url =~ "/a/#{destination_county_domain}/receiver/"
        assert Test.Xml.attr(doc, "case:nth-of-type(1)", "case_id") == transferred_case_id
        assert Test.Xml.text(doc, "case:nth-of-type(1) create owner_id") == Test.Fixtures.test_county_2_location_id()
        assert Test.Xml.text(doc, "case:nth-of-type(1) update full_name") == "Full Name from CommCare"
        assert Test.Xml.text(doc, "case:nth-of-type(1) update address") == "Address from CommCare"
        assert Test.Xml.text(doc, "case:nth-of-type(1) update phone_number") == "555-NEW-PHONE-FROM-ECLRS"

        assert Test.Xml.attr(doc, "case:nth-of-type(2)", "case_id") == transferred_initial_lab_result.case_id
        assert Test.Xml.text(doc, "case:nth-of-type(2) update accession_number") == transferred_initial_lab_result.accession_number
        assert Test.Xml.text(doc, "case:nth-of-type(3) update accession_number") == initial_county_new_lab_result.accession_number
        assert Test.Xml.attr(doc, "case:nth-of-type(3)", "case_id") != initial_county_new_lab_result.case_id

        {:ok, %{status_code: 201, body: Test.Fixtures.commcare_submit_response(:success)}}
      end)

      :ok = CommcareCaseLoader.perform(%{attempt: 1, args: %{"case_id" => initial_case_id, "county_id" => county_fips}})

      {:ok, [reloaded_destination_index_case]} = Commcare.get_index_cases(person, county_id: destination_county_fips)
      assert reloaded_destination_index_case.data["full_name"] == "Full Name from CommCare"
      assert reloaded_destination_index_case.data["phone_number"] == "555-NEW-PHONE-FROM-ECLRS"
      assert reloaded_destination_index_case.data["address"] == "Address from CommCare"
      assert reloaded_destination_index_case.data["owner_id"] == Test.Fixtures.test_county_2_location_id()

      initial_index_case |> assert_events(["send_to_commcare_rerouted"])
      transferred_index_case |> assert_events(["updated_from_commcare", "send_to_commcare_succeeded"])
    end

    """
    when the case was transferred to another county, but the destination case cannot be found,
    it fails and logs an error message
    """
    |> test do
      case_id = "case-id-abcd1234"
      county_fips = Test.Fixtures.test_county_1_fips()
      county_domain = Test.Fixtures.test_county_1_domain()
      destination_county_fips = Test.Fixtures.test_county_2_fips()
      destination_county_domain = Test.Fixtures.test_county_2_domain()

      {:ok, county} = ECLRS.find_or_create_county(county_fips)
      {:ok, person} = %{data: %{}, patient_keys: ["123"]} |> Test.Factory.person() |> Commcare.create_person()

      {:ok, _index_case} =
        %{case_id: case_id, data: %{}, person_id: person.id, county_id: county.id}
        |> Commcare.create_index_case()

      initial_case_response = %{
        "case_id" => case_id,
        "properties" => %{
          "owner_id" => Test.Fixtures.test_county_1_location_id(),
          "external_id" => "external-id-123",
          "transfer_destination_county_id" => destination_county_fips
        }
      }

      NYSETL.HTTPoisonMock
      |> stub(:get, fn url, _headers, _opts ->
        cond do
          url =~ "/a/#{county_domain}/api/v0.5/case/#{case_id}/" ->
            {:ok, %{status_code: 200, body: initial_case_response |> Jason.encode!()}}

          url =~ "/a/#{destination_county_domain}/api/v0.5/case/?external_id=external-id-123" ->
            {:ok, %{status_code: 404, body: "not found"}}

          true ->
            raise "url was not mocked: #{url}"
        end
      end)

      log =
        capture_log(fn ->
          {:error, message} = CommcareCaseLoader.perform(%{attempt: 1, args: %{"case_id" => case_id, "county_id" => county_fips}})
          assert message =~ "case_id=case-id-abcd1234 county_domain=uk-midsomer-cdcms was transferred but target case was not found"
        end)

      assert log =~ "case_id=case-id-abcd1234 county_domain=uk-midsomer-cdcms was transferred but target case was not found"
    end

    """
    when the case was transferred to another county, and a cycle is detected,
    it fails and logs an error message
    """
    |> test do
      case_id = "case-id-abcd1234"
      destination_case_id = "destination-case-id-456"

      county_fips = Test.Fixtures.test_county_1_fips()
      county_domain = Test.Fixtures.test_county_1_domain()
      destination_county_fips = Test.Fixtures.test_county_2_fips()
      destination_county_domain = Test.Fixtures.test_county_2_domain()

      {:ok, county} = ECLRS.find_or_create_county(county_fips)
      {:ok, person} = %{data: %{}, patient_keys: ["123"]} |> Test.Factory.person() |> Commcare.create_person()

      {:ok, index_case} =
        %{case_id: case_id, data: %{}, person_id: person.id, county_id: county.id}
        |> Commcare.create_index_case()

      initial_case_response = %{
        "case_id" => case_id,
        "properties" => %{
          "owner_id" => Test.Fixtures.test_county_1_location_id(),
          "external_id" => "external-id-123",
          "transfer_destination_county_id" => destination_county_fips
        }
      }

      destination_case_response = %{
        objects: [
          %{
            "case_id" => destination_case_id,
            "properties" => %{
              "owner_id" => Test.Fixtures.test_county_2_location_id(),
              "external_id" => "external-id-123",
              "transfer_destination_county_id" => county_fips,
              "transfer_source_case_id" => case_id
            }
          }
        ]
      }

      NYSETL.HTTPoisonMock
      |> stub(:get, fn url, _headers, _opts ->
        cond do
          url =~ "/a/#{county_domain}/api/v0.5/case/#{case_id}/" ->
            {:ok, %{status_code: 200, body: initial_case_response |> Jason.encode!()}}

          url =~ "/a/#{destination_county_domain}/api/v0.5/case/?external_id=external-id-123" ->
            {:ok, %{status_code: 200, body: destination_case_response |> Jason.encode!()}}

          true ->
            raise "url was not mocked: #{url}"
        end
      end)

      log =
        capture_log(fn ->
          assert CommcareCaseLoader.perform(%{attempt: 1, args: %{"case_id" => case_id, "county_id" => county_fips}}) == :discard
        end)

      assert log =~ "Case transfer cycle detected case-id-abcd1234@uk-midsomer-cdcms -> destination-case-id-456@sw-yggdrasil-cdcms"
      index_case |> assert_events(["send_to_commcare_discarded"])
    end
  end
end
