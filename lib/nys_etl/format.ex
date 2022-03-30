defmodule NYSETL.Format do
  @moduledoc """
  Given a thing, format that thing for output.
  """

  def format(value, opts \\ [])

  def format(nil, _), do: ""
  def format(binary, _) when is_binary(binary), do: binary

  def format(%Date{} = date, _opts), do: Date.to_iso8601(date)

  def format(%DateTime{} = datetime, opts) do
    timezone = opts |> Keyword.get(:timezone, "America/New_York")

    datetime
    |> Timex.to_datetime(timezone)
    |> Date.to_iso8601()
  end

  def format(int, pad: pad) when is_integer(int), do: int |> format() |> String.pad_leading(pad, "0")
  def format(int, _opts) when is_integer(int), do: int |> Integer.to_string()

  def us_phone_number(phone_number) when byte_size(phone_number) == 10 do
    "1" <> phone_number
  end

  def us_phone_number(phone_number), do: phone_number

  def age(birthdate), do: age(birthdate, Date.utc_today())

  def age(%Date{} = birthdate, as_of) do
    Timex.diff(as_of, birthdate, :years)
    |> to_string()
  end

  def age(nil, _), do: ""

  def age_range(birthdate), do: age_range(birthdate, Date.utc_today())

  def age_range(%Date{} = birthdate, as_of) do
    Timex.diff(as_of, birthdate, :years)
    |> case do
      age when age >= 0 and age <= 17 -> "0 - 17"
      age when age >= 18 and age <= 59 -> "18 - 59"
      age when age >= 60 -> "60+"
    end
  end

  def age_range(nil, _), do: ""
end
