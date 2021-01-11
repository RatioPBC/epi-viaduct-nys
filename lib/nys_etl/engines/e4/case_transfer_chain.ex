defmodule NYSETL.Engines.E4.CaseTransferChain do
  @moduledoc """
  Uses Commcare.Api to understand transfer chains and creates index case records to reflect the data in CommCare.
  """

  require Logger

  import Ecto.Query, only: [from: 1, where: 3]

  alias Euclid.Exists
  alias NYSETL.Commcare.{Api, County}
  alias NYSETL.Engines.E4.{CaseIdentifier, PatientCaseData}
  alias NYSETL.Monitoring.Oban.ErrorReporter
  alias NYSETL.Commcare
  alias NYSETL.Repo

  @spec follow_transfers(NYSETL.Commcare.CaseIdentifier.t(), Oban.Job.t(), [PatientCaseData.t()]) :: [
          PatientCaseData.t() | :cycle_detected | :not_found | any()
        ]
  def follow_transfers(%CaseIdentifier{} = case_identifier, job, transfer_chain \\ []) do
    case get_patient_case_data(case_identifier, job) do
      {:ok, {:found, data}} ->
        current_domain = case_identifier.county_domain
        patient_case_data = PatientCaseData.new(data, current_domain)

        case get_transfer_destination_county(patient_case_data, current_domain, transfer_chain) do
          :not_a_transfer ->
            [patient_case_data | transfer_chain]

          {:ok, %{domain: ^current_domain} = _transfer_destination_county} ->
            [patient_case_data | transfer_chain]

          {:ok, transfer_destination_county} ->
            CaseIdentifier.new(
              external_id: patient_case_data.external_id,
              county_domain: transfer_destination_county.domain,
              transfer_source_case_id: patient_case_data.case_id
            )
            |> follow_transfers(job, [patient_case_data | transfer_chain])

          :cycle_detected ->
            Logger.error(
              "[#{__MODULE__}] Case transfer cycle detected #{
                describe([patient_case_data | transfer_chain])
                |> Enum.reverse()
                |> Enum.join(" -> ")
              }"
            )

            [:cycle_detected | transfer_chain]

          {:not_found, error} ->
            [error | transfer_chain]
        end

      {:ok, {:not_found, nil}} ->
        [:not_found | transfer_chain]

      other ->
        [other | transfer_chain]
    end
  end

  # TODO: Change the Sentry calls below to include the "raw" case_identifier, but make sure that CaseIdentifier has a proper
  # serialiser:
  #
  # 2020-11-05T21:20:20.797Z [warn] Failed to send Sentry event. Unable to encode JSON Sentry error -
  # %Protocol.UndefinedError{description: "Jason.Encoder protocol must always be explicitly implemented.
  # If you own the struct, you can derive the implementation specifying which fields should be encoded to JSON:
  #     @derive {Jason.Encoder, only: [....]}\n    defstruct ...
  # It is also possible to encode all fields, although this should be used carefully to avoid accidentally leaking private information when new fields are added:
  #     @derive Jason.Encoder\n    defstruct ...
  # Finally, if you don't own the struct you want to encode to JSON, you may use Protocol.derive/3 placed outside of any module:
  #     Protocol.derive(Jason.Encoder, NameOfTheStruct, only: [...])\n    Protocol.derive(Jason.Encoder, NameOfTheStruct)\n", protocol: Jason.Encoder,
  # value: %NYSETL.Engines.E4.CaseIdentifier{case_id: nil, county_domain: "ny-cortland-cdcms", county_id: nil, external_id: "P462684", transfer_source_case_id: "7da15831-4e51-4815-9996-de8e80981db4"}}

  def get_patient_case_data(%CaseIdentifier{} = case_identifier, job) do
    fetch_case(case_identifier)
    |> case do
      {:ok, data} ->
        {:ok, {:found, data}}

      {:error, :not_found} ->
        {:ok, {:not_found, nil}}

      {:no_case_matches, {case_id, cases}} ->
        reason = "No destination case matches source case id"
        ErrorReporter.post_to_sentry(reason, job, %{case_identifier: CaseIdentifier.describe(case_identifier), cases: cases})

        Logger.error(
          "[#{__MODULE__}] Error when trying to get #{CaseIdentifier.describe(case_identifier)}, reason=#{reason}, case_id=#{case_id}, cases=#{
            inspect(cases)
          }"
        )

        {:error, reason}

      {:more_than_one, cases} ->
        reason = "More than one case matches source case id"
        ErrorReporter.post_to_sentry(reason, job, %{case_identifier: CaseIdentifier.describe(case_identifier), cases: cases})

        Logger.error(
          "[#{__MODULE__}] Error when trying to get #{CaseIdentifier.describe(case_identifier)}, reason=#{reason}, cases=#{inspect(cases)}"
        )

        {:error, reason}

      {:error, reason} when is_atom(reason) or is_binary(reason) ->
        ErrorReporter.post_to_sentry(inspect(reason), job, %{case_identifier: CaseIdentifier.describe(case_identifier)})
        Logger.error("[#{__MODULE__}] Error when trying to get #{CaseIdentifier.describe(case_identifier)}, reason=#{reason}")
        {:error, reason}

      {:error, %{body: body, status_code: status_code}} ->
        ErrorReporter.post_to_sentry(body, job, %{case_identifier: CaseIdentifier.describe(case_identifier)})
        Logger.error("[#{__MODULE__}] Error when trying to get #{CaseIdentifier.describe(case_identifier)}, status_code=#{status_code}")
        {:error, body}

      {:error, other} ->
        ErrorReporter.post_to_sentry(inspect(other), job, %{case_identifier: CaseIdentifier.describe(case_identifier)})
        Logger.error("[#{__MODULE__}] Error when trying to get #{CaseIdentifier.describe(case_identifier)}, error: #{inspect(other)}")
        {:error, "error in get_case"}
    end
  end

  @spec fetch_case(NYSETL.Commcare.CaseIdentifier.t()) ::
          {:error, any} | {:more_than_one, [...]} | {:no_case_matches, {binary, any}} | {:ok, any}
  def fetch_case(%CaseIdentifier{case_id: case_id, county_domain: county_domain}) when is_binary(case_id),
    do: Api.get_case(commcare_case_id: case_id, county_domain: county_domain)

  def fetch_case(%CaseIdentifier{external_id: external_id, county_domain: county_domain, transfer_source_case_id: transfer_source_case_id})
      when is_binary(external_id) and is_binary(transfer_source_case_id) do
    with {:ok, list} <- Api.get_transfer_cases(external_id: external_id, county_domain: county_domain) do
      case length(list) do
        0 ->
          # it's possible that there is a case in the destination county with a matching transfer_source_case_id,
          # so we look in our DB for such a case. If such a case exists, it is most likely a duplicate, so we attempt
          # to follow the duplicate chain.
          try_transfer_source_case_id_match(county_domain, transfer_source_case_id)

        1 ->
          {:ok, hd(list)}

        _ ->
          list
          |> Enum.filter(&match?(%{"properties" => %{"transfer_source_case_id" => ^transfer_source_case_id}}, &1))
          |> case do
            [the_case] ->
              {:ok, the_case}

            [] ->
              # it's possible that there is a case with a matching transfer_source_case_id that does not have an
              # external_id. As an example, see:
              # https://www.notion.so/geometer/Mutiple-cases-whose-external_id-matches-but-without-matching-transfer_source_case_id-b43b53cce12a45ac9530e7fc59bd09d5
              try_transfer_source_case_id_match(county_domain, transfer_source_case_id)

            more_than_one ->
              {:more_than_one, more_than_one}
          end
      end
    else
      other -> other
    end
  end

  def fetch_case(%CaseIdentifier{county_domain: county_domain, transfer_source_case_id: transfer_source_case_id})
      when is_binary(county_domain) and is_binary(transfer_source_case_id) do
    case get_transfer_destination_cases(transfer_source_case_id) do
      [] ->
        {:no_case_matches, {transfer_source_case_id, []}}

      [index_case] ->
        case fetch_case(CaseIdentifier.new(case_id: index_case.case_id, county_domain: county_domain)) do
          {:error, :not_found} -> {:no_case_matches, {transfer_source_case_id, []}}
          {:ok, case} -> {:ok, case}
        end

      more_than_one ->
        {:more_than_one, more_than_one}
    end
  end

  def try_transfer_source_case_id_match(county_domain, transfer_source_case_id) do
    result = fetch_case(CaseIdentifier.new(county_domain: county_domain, transfer_source_case_id: transfer_source_case_id))

    case result do
      {:ok, case} -> case |> follow_duplicate_chain(county_domain, [])
      _ -> result
    end
  end

  def get_transfer_destination_county(patient_case_data, current_domain, transfer_chain) do
    if Exists.present?(patient_case_data.transfer_destination_county_id) do
      case County.get(fips: patient_case_data.transfer_destination_county_id) do
        {:ok, %{domain: new_target_county_domain} = county} ->
          cond do
            new_target_county_domain == current_domain ->
              :not_a_transfer

            transfer_chain |> contains_county_domain?(new_target_county_domain) ->
              :cycle_detected

            true ->
              {:ok, county}
          end

        {:non_participating, _} ->
          County.statewide_county()

        other ->
          {:not_found, other}
      end
    else
      :not_a_transfer
    end
  end

  def contains_county_domain?(chain, search_county_domain) do
    Enum.any?(chain, fn
      %PatientCaseData{county_domain: county_domain} -> county_domain == search_county_domain
      _ -> false
    end)
  end

  def describe(chain) when is_list(chain) do
    Enum.map(chain, fn
      %PatientCaseData{case_id: case_id, county_domain: county_domain} -> "#{case_id}@#{county_domain}"
      other -> other
    end)
  end

  @spec resolve([any]) :: {any, :no_transfer | :transfer}
  def resolve(chain) when is_list(chain) do
    end_of_chain =
      if Enum.all?(chain, &patient_case_data?/1),
        do: {:ok, List.first(chain)},
        else: chain |> Enum.reverse() |> Enum.find(&(!patient_case_data?(&1)))

    transfer_status = if length(chain) > 1, do: :transfer, else: :no_transfer
    {end_of_chain, transfer_status}
  end

  defp patient_case_data?(%PatientCaseData{}), do: true
  defp patient_case_data?(_), do: false

  def get_transfer_destination_cases(transfer_source_case_id) do
    from(index_case in Commcare.IndexCase)
    |> where([ic], fragment("(data->>'transfer_source_case_id' = ?)", ^transfer_source_case_id))
    |> Repo.all()
  end

  defp follow_duplicate_chain(commcare_case, county_domain, visited_cases) do
    %{"case_id" => case_id, "properties" => properties} = commcare_case
    duplicate_of_case_id = properties["duplicate_of_case_id"]

    cond do
      Enum.member?(visited_cases, duplicate_of_case_id) ->
        # there is a cycle, so just pick a case
        Logger.info("[#{__MODULE__}] Found a cycle in the duplicate chain for case_id #{duplicate_of_case_id}")
        {:ok, commcare_case}

      duplicate_of_case_id == nil ->
        {:ok, commcare_case}

      true ->
        fetch_result = fetch_case(%CaseIdentifier{case_id: duplicate_of_case_id, county_domain: county_domain})

        case fetch_result do
          {:error, :not_found} ->
            # The duplicate chain dead ends, so just return the case that we have
            Logger.info("[#{__MODULE__}] Found a dead-end duplicate chain for case_id #{duplicate_of_case_id}")
            {:ok, commcare_case}

          {:ok, next_case} ->
            follow_duplicate_chain(next_case, county_domain, [case_id | visited_cases])
        end
    end
  end
end
