defmodule NYSETL.ECLRS do
  @moduledoc """
  Context to encapsulate Ecto schemas around data extracted from ECLRS files.
  """

  import Ecto.Query
  alias Euclid.Extra
  alias NYSETL.ECLRS
  alias NYSETL.Repo

  def change_about(%ECLRS.About{} = about, attrs) do
    about
    |> ECLRS.About.changeset(attrs)
  end

  def find_or_create_county(id) do
    get_county(id)
    |> case do
      {:ok, county} ->
        {:ok, county}

      {:error, :not_found} ->
        %ECLRS.County{}
        |> ECLRS.County.changeset(%{id: id})
        |> Repo.insert()
        |> case do
          {:ok, county} ->
            {:ok, county}

          {:error, %Ecto.Changeset{}} ->
            get_county(id)
        end
    end
  end

  def create_about(attrs) do
    %ECLRS.About{}
    |> ECLRS.About.changeset(attrs)
    |> Repo.insert()
  end

  def create_file(attrs) do
    %ECLRS.File{}
    |> ECLRS.File.changeset(attrs)
    |> Repo.insert()
  end

  def create_test_result(message) do
    message
    |> ECLRS.TestResult.changeset()
    |> Repo.insert()
  end

  def fingerprint(%ECLRS.TestResult{} = tr) do
    "#{tr.patient_dob}#{tr.patient_name_last}#{tr.patient_name_first}"
    |> NYSETL.Crypto.sha256()
  end

  def finish_processing_file(%ECLRS.File{} = file, statistics: statistics) do
    file
    |> ECLRS.File.changeset(%{statistics: statistics, processing_completed_at: DateTime.utc_now()})
    |> Repo.update()
  end

  def get_county(id) do
    ECLRS.County
    |> Repo.get(id)
    |> case do
      nil -> {:error, :not_found}
      county -> {:ok, county}
    end
  end

  def get_file(query) do
    ECLRS.File
    |> Repo.get_by(query)
    |> case do
      nil -> {:error, :not_found}
      file -> {:ok, file}
    end
  end

  def get_about(query) do
    ECLRS.About
    |> Repo.get_by(query)
    |> case do
      nil -> {:error, :not_found}
      about -> {:ok, about}
    end
  end

  def save_event(%ECLRS.TestResult{} = test_result, event_name) when is_binary(event_name) do
    save_event(test_result, type: event_name)
  end

  def save_event(%ECLRS.TestResult{} = test_result, event_attrs) when is_list(event_attrs) do
    %ECLRS.TestResultEvent{}
    |> ECLRS.TestResultEvent.changeset(%{test_result_id: test_result.id, event: Enum.into(event_attrs, %{})})
    |> Repo.insert()

    # TODO: look at Commcare.save_event for some inspiration, like `|> do_save_event()`
  end

  def update_file(%ECLRS.File{} = file, attrs) do
    file
    |> ECLRS.File.changeset(attrs)
    |> Repo.update()
  end

  def update_last_seen_file(abouts, file) do
    ids = abouts |> Extra.Enum.pluck(:id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(about in ECLRS.About, where: about.id in ^ids)
    |> Repo.update_all(
      set: [
        last_seen_file_id: file.id,
        last_seen_at: now,
        updated_at: now
      ]
    )

    :ok
  end
end
