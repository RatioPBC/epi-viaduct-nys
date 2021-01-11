defmodule NYSETL.Commcare.Api do
  @moduledoc """
  Wraps calls to CommCare.
  """

  @http_client Application.compile_env!(:nys_etl, :http_client)
  @limit 100

  require Logger

  def get_county_list(cache_control \\ :refer_to_config) do
    cached? = use_cache?(cache_control, :county_list_cache_enabled)
    get_cacheable_list(:county_list, &get_county_list!/0, cached?)
  end

  defp use_cache?(:refer_to_config, cache_enabled_config_key), do: Application.get_env(:nys_etl, cache_enabled_config_key)
  defp use_cache?(:cache_enabled, _), do: true
  defp use_cache?(:cache_disabled, _), do: false

  defp get_cacheable_list(_cache_key, get_fn, false), do: get_fn.() |> Tuple.append(:cache_skip)

  defp get_cacheable_list(cache_key, get_fn, true) do
    Cachex.fetch(:cache, cache_key, fn _ ->
      case get_fn.() do
        {:ok, resp} -> {:commit, resp}
        {:error, _reason} = error -> {:ignore, error}
      end
    end)
    |> case do
      {:commit, value} -> {:ok, value, :cache_miss}
      other -> other |> Tuple.append(:cache_hit)
    end
  end

  defp get_county_list!() do
    root_domain = Application.get_env(:nys_etl, :commcare_root_domain)

    case get("/a/#{root_domain}/api/v0.5/fixture/?fixture_type=county_list") do
      {:ok, %{status_code: 200, body: body}} ->
        :telemetry.execute([:api, :commcare, :get_county_list, :success], %{count: 1})
        {:ok, body |> Jason.decode!() |> Map.get("objects")}

      {:ok, other} ->
        :telemetry.execute([:api, :commcare, :get_county_list, :error], %{count: 1})
        {:error, other}

      {:error, reason} ->
        :telemetry.execute([:api, :commcare, :get_county_list, :error], %{count: 1})
        {:error, reason}
    end
  end

  @doc """
  Get list of cases by type from county domain.

  ## Options

    * `:county_domain` : ny-statewide-cdcms
    * `:type` : patient | lab_result
    * `:offset` : 0
    * `:full` : include child cases : true | false
    * `:modified_since` : start of day : ~D[2020-07-20]
  """
  def get_cases(opts) do
    county_domain = Keyword.fetch!(opts, :county_domain)
    type = Keyword.fetch!(opts, :type)

    full = Keyword.get(opts, :full, false)
    modified_since = Keyword.get(opts, :modified_since)
    limit = Keyword.get(opts, :limit, @limit)
    offset = Keyword.get(opts, :offset, 0)

    query_params = [type: type, limit: limit, offset: offset]
    query_params = if full, do: Keyword.put(query_params, :child_cases__full, "true"), else: query_params
    query_params = if modified_since, do: Keyword.put(query_params, :server_date_modified_start, Date.to_iso8601(modified_since)), else: query_params

    query = URI.encode_query(query_params)

    Logger.debug("[#{__MODULE__}/get_cases] domain=#{county_domain} #{query}")

    case get("/a/#{county_domain}/api/v0.5/case/?#{query}") do
      {:ok, %{status_code: 200, body: response_body}} ->
        :telemetry.execute([:api, :commcare, :get_cases, :success], %{count: 1})

        case Jason.decode(response_body) do
          {:ok, decoded_body} ->
            {:ok, decoded_body |> Map.take(["objects"]) |> Map.merge(%{"next_offset" => get_next_offset(offset, decoded_body, limit)})}

          {:error, reason} ->
            {:something, :is_wrong} = {reason, response_body}
        end

      {:ok, other} ->
        :telemetry.execute([:api, :commcare, :get_cases, :error], %{count: 1})
        {:error, other}

      {:error, reason} ->
        :telemetry.execute([:api, :commcare, :get_cases, :error], %{count: 1})
        {:error, reason}
    end
  end

  defp get_next_offset(offset, decoded_body, limit) do
    next =
      decoded_body
      |> Map.get("meta")
      |> Map.get("next")

    if next == nil, do: nil, else: offset + limit
  end

  @spec get_case([{:commcare_case_id, any} | {:county_domain, any}, ...]) :: {:error, any} | {:ok, any}
  def get_case(commcare_case_id: case_id, county_domain: county_domain) do
    Logger.info("checking commcare case_id='#{case_id} for #{county_domain}")

    case get_case_from_url("/a/#{county_domain}/api/v0.5/case/#{case_id}/?format=json&child_cases__full=true") do
      {:body, body} ->
        {:ok, Jason.decode!(body)}

      other ->
        other
    end
  end

  @spec get_transfer_cases([{:county_domain, binary()}, {:external_id, binary()}]) :: {:error, any} | {:ok, [map()]}
  def get_transfer_cases(external_id: external_id, county_domain: county_domain) do
    Logger.info("checking commcare external_id='#{external_id}' for #{county_domain}")

    case get_case_from_url("/a/#{county_domain}/api/v0.5/case/?external_id=#{external_id}") do
      {:body, body} ->
        cases =
          body
          |> Jason.decode!()
          |> Map.get("objects")

        {:ok, cases}

      other ->
        other
    end
  end

  def get_case_from_url(request_path) do
    case get(request_path) do
      {:ok, %{status_code: 200, body: response_body}} ->
        :telemetry.execute([:api, :commcare, :get_case, :success], %{count: 1})
        {:body, response_body}

      {:ok, %{status_code: 404}} ->
        :telemetry.execute([:api, :commcare, :get_case, :not_found], %{count: 1})
        {:error, :not_found}

      {_, %{status_code: 429}} ->
        :telemetry.execute([:api, :commcare, :get_case, :rate_limited], %{count: 1})
        {:error, :rate_limited}

      {:ok, other} ->
        :telemetry.execute([:api, :commcare, :get_case, :error], %{count: 1})
        {:error, other}

      {:error, reason} ->
        :telemetry.execute([:api, :commcare, :get_case, :error], %{count: 1})
        {:error, reason}
    end
  end

  def get_case_list(owner_id: owner_id, county_domain: county_domain) do
    case get("/a/#{county_domain}/api/v0.5/case/?owner_id=#{owner_id}") do
      {:ok, %{status_code: 200, body: response_body}} -> {:ok, response_body}
      {:ok, other} -> {:error, other}
      {:error, reason} -> {:error, reason}
    end
  end

  def ping() do
    case get("/accounts/login/") do
      {:ok, %{status_code: 200, body: body}} -> {:ok, body}
      {:ok, other} -> {:error, other}
      {:error, reason} -> {:error, reason}
    end
  end

  def post_case(case_xml, county_domain) when is_binary(case_xml) do
    case post("/a/#{county_domain}/receiver/", case_xml) do
      {:ok, %{status_code: 201, body: response_body} = response} ->
        :telemetry.execute([:api, :commcare, :post_case, :not_found], %{count: 1})
        if response_body =~ "submit_success", do: {:ok, response}, else: {:error, response}

      {:ok, %{status_code: 429}} ->
        :telemetry.execute([:api, :commcare, :post_case, :rate_limited], %{count: 1})
        {:error, :rate_limited}

      {:ok, other} ->
        :telemetry.execute([:api, :commcare, :post_case, :error], %{count: 1})
        {:error, other}

      {:error, reason} ->
        :telemetry.execute([:api, :commcare, :post_case, :error], %{count: 1})
        {:error, reason}
    end
  end

  # delegate to HTTPoison.get
  #    recv_timeout: 60s, since the default of 5s is too little
  defp get(relative_path) do
    send_telemetry(:get, relative_path)

    @http_client.get(
      url(relative_path),
      [{"Authorization", api_key_auth()}, {"User-Agent", user_agent()}],
      follow_redirect: true,
      max_redirect: 10,
      recv_timeout: 60_000
    )
  end

  defp post(relative_path, xml_body) do
    send_telemetry(:post, relative_path)
    # :hackney_trace.enable(:max, :io)

    @http_client.post(
      url(relative_path),
      xml_body,
      [{"Authorization", api_key_auth()}, {"Content-Type", "text/xml"}, {"User-Agent", user_agent()}]
    )
  end

  defp api_key_auth(), do: "ApiKey #{Application.get_env(:nys_etl, :commcare_api_key_credentials)}"
  defp send_telemetry(action, path), do: :telemetry.execute([:commcare_client, :request], %{request: {action, path}})
  defp url(relative_path), do: URI.merge(Application.get_env(:nys_etl, :commcare_base_url), relative_path) |> URI.to_string()
  defp user_agent(), do: "#{:hackney_request.default_ua()} (+http://geometer.io/viaduct-nys)"
end
