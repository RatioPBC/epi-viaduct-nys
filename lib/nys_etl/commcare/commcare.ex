defmodule NYSETL.Commcare do
  @moduledoc """
  Context to encapsulate Ecto schemas around data prepared to be loaded into CommCare.
  """

  import Ecto.Query, only: [from: 1, from: 2, where: 3, join: 5, order_by: 2]
  alias NYSETL.Commcare
  alias NYSETL.Repo

  def add_patient_key(person, patient_key) do
    person
    |> Commcare.Person.changeset(%{patient_keys: [patient_key | person.patient_keys]})
    |> Repo.update()
  end

  def create_index_case(attrs, meta \\ nil) do
    %Commcare.IndexCase{}
    |> Commcare.IndexCase.changeset(attrs)
    |> insert_with_paper_trail(meta)
  end

  def create_lab_result(attrs, meta \\ nil),
    do:
      %Commcare.LabResult{}
      |> Commcare.LabResult.changeset(attrs)
      |> insert_with_paper_trail(meta)

  def create_person(attrs),
    do:
      %Commcare.Person{}
      |> Commcare.Person.changeset(attrs)
      |> insert_with_paper_trail()

  def external_id(%Commcare.Person{id: id}), do: "P#{id}"

  def get_index_cases(%Commcare.Person{id: person_id} = person, county_id: county_id, accession_number: accession_number) do
    from(index_case in Commcare.IndexCase, distinct: index_case.id)
    |> where([ic], ic.person_id == ^person_id and ic.county_id == ^county_id)
    |> join(:inner, [ic], labs in assoc(ic, :lab_results), as: :lab_results)
    |> where([ic, lab_results: labs], labs.accession_number == ^accession_number)
    |> order_by(asc: :id)
    |> Repo.all()
    |> case do
      [] -> get_index_cases(person, county_id: county_id)
      index_cases -> {:ok, index_cases}
    end
  end

  def get_index_cases(%Commcare.Person{id: person_id}, county_id: county_id) do
    from(index_case in Commcare.IndexCase)
    |> where([ic], ic.person_id == ^person_id and ic.county_id == ^county_id)
    |> order_by(asc: :id)
    |> Repo.all()
    |> case do
      [] -> {:error, :not_found}
      index_cases -> {:ok, index_cases}
    end
  end

  def get_index_case(case_id: case_id, county_id: county_id) do
    Commcare.IndexCase
    |> Repo.get_by(case_id: case_id, county_id: county_id)
    |> case do
      nil -> {:error, :not_found}
      index_case -> {:ok, index_case}
    end
  end

  def get_lab_results(%Commcare.IndexCase{id: index_case_id}, accession_number: accession_number) do
    from(lab_result in Commcare.LabResult)
    |> where([rl], rl.index_case_id == ^index_case_id and rl.accession_number == ^accession_number)
    |> Repo.all()
    |> case do
      [] -> {:error, :not_found}
      lab_results -> {:ok, lab_results}
    end
  end

  def get_lab_results(%Commcare.IndexCase{} = index_case) do
    index_case
    |> Repo.preload(lab_results: from(lr in Commcare.LabResult, order_by: [asc: lr.inserted_at, asc: lr.id]))
    |> Map.get(:lab_results)
  end

  def get_person(patient_key: patient_key) do
    from(person in Commcare.Person)
    |> where([person], ^patient_key in person.patient_keys)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      person -> {:ok, person}
    end
  end

  def get_person(dob: dob, name_first: name_first, name_last: name_last) do
    Commcare.Person
    |> Repo.get_by(dob: dob, name_first: name_first, name_last: name_last)
    |> case do
      nil -> {:error, :not_found}
      person -> {:ok, person}
    end
  end

  def get_person(dob: dob, full_name: full_name) do
    from(person in Commcare.Person)
    |> where(
      [person],
      person.dob == ^dob and
        fragment("name_last  !~ '\\S\\('") and
        fragment("name_first !~ '\\S\\('") and
        fragment(
          """
          to_tsvector('simple', lower(?)) @@
          array_to_string(
            regexp_split_to_array(lower(concat_ws(' ', name_first, name_last)), E'\\\\s+'),
            ' & '
          )::tsquery
          """,
          ^full_name
        ) == true
    )
    |> Repo.first()
    |> case do
      nil -> {:error, :not_found}
      person -> {:ok, person}
    end
  end

  def save_event(%Commcare.IndexCase{} = index_case, event_name) when is_binary(event_name) do
    save_event(index_case, type: event_name)
  end

  def save_event(%Commcare.IndexCase{} = index_case, event_attrs) when is_list(event_attrs) do
    %Commcare.IndexCaseEvent{}
    |> Commcare.IndexCaseEvent.changeset(%{index_case_id: index_case.id, event: Enum.into(event_attrs, %{})})
    |> Repo.insert()
    |> do_save_event()
  end

  defp do_save_event({:error, _changeset}) do
    {:error, nil}
  end

  defp do_save_event({:ok, index_case_event}) do
    %Commcare.IndexCaseEvent{event: event} = Repo.preload(index_case_event, :event)
    {:ok, event}
  end

  def update_index_case(%Commcare.IndexCase{} = index_case, attrs, meta \\ nil) do
    index_case
    |> update_with_paper_trail(&Commcare.IndexCase.changeset/2, attrs, meta)
  end

  def update_lab_result(%Commcare.LabResult{} = lab_result, attrs, meta \\ nil) do
    lab_result
    |> update_with_paper_trail(&Commcare.LabResult.changeset/2, attrs, meta)
  end

  def update_index_case_from_commcare_data(%Commcare.IndexCase{} = index_case, %{"properties" => properties} = patient_case) do
    data = properties |> NYSETL.Extra.Map.merge_empty_fields(index_case.data)
    Commcare.update_index_case(index_case, %{closed: patient_case["closed"], data: data}, %{fetched_from_commcare: properties})
  end

  defp update_with_paper_trail(model, make_changeset, attrs, meta) do
    model
    |> make_changeset.(attrs)
    |> case do
      %{valid?: true, changes: map} when map == %{} ->
        {:ok, model}

      changeset ->
        changeset
        |> PaperTrail.update(meta: meta)
        |> unwrap_paper_trail_response()
    end
  end

  defp insert_with_paper_trail(changeset, meta \\ nil) do
    changeset
    |> PaperTrail.insert(meta: meta)
    |> unwrap_paper_trail_response()
  end

  defp unwrap_paper_trail_response({:ok, result}), do: {:ok, result |> Map.get(:model)}

  defp unwrap_paper_trail_response({:error, changeset}), do: {:error, changeset}
end
