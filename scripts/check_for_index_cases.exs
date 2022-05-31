import Ecto.Query

alias NYSETL.Repo
alias NYSETL.ECLRS.TestResult
alias NYSETL.Commcare.IndexCase
alias NYSETL.Commcare.County
alias NYSETL.Commcare.Api
# alias NYSETL.Commcare.CountiesCache

# GenServer.start_link(CountiesCache.Server, [source: fn -> NYSETL.Commcare.Api.http_get_county_list() end, name: NYSETL.Commcare.Api])

# list of test result IDs
test_result_ids = [7999358, 7999459, 7999430, 7999369, 7999399, 7999385, 7999388, 7999276, 7999248, 7999273, 7999363, 7999367, 7999362, 7999305, 7999303, 7999333, 7999302, 7999373, 7999304, 7999438, 7999328, 7999271, 7999389, 7999372, 7999279, 7999378, 7999312, 7999321, 7999416, 7999382, 7999450, 7999465, 7999283, 7999314, 7999448, 7999407, 7999680, 7999760, 7999596, 7999515, 7999552, 7999581, 7999586, 7999790, 7999591, 7999756, 7999511, 7999514, 7999556, 7999482, 7999619, 7999774, 7999727, 7999653, 7999661, 7999538, 7999644, 7999600, 7999498, 7999656, 7999688, 7999858, 7999856, 7999817, 7999883, 7999857, 7999913, 7999994, 7999944, 7999945, 7999886, 7999969, 8000011, 7999937, 8000016, 8000320, 8002380, 8002351, 8002276, 8002360, 8002303, 8002307, 8002341, 8002272, 8002364, 8002239, 8002425, 8002541, 8002507, 8002540, 8002413, 8002542, 8002459, 8002411, 8002506, 8002642, 8002518, 8002539, 8002585, 8002460, 8002544, 8002412, 8002571, 8002436, 8002474, 8002561, 8002708, 8002620, 8002534, 8002566, 8002445, 8002720, 8002470, 8002618, 8002483, 8002440, 8002435, 8002710, 8002617, 8002490, 8002626, 8002627, 8002667, 8002615, 8002624, 8002629, 8002486, 8002718, 8002747, 8002669, 8002709, 8002574, 8002662, 8002531, 8002569, 8002583, 8002676, 8002674, 8002605, 8002697, 8002756, 8002482, 8002601, 8002598, 8002416, 8002600, 8002691, 8002465, 8002595, 8002693]

# get the test result events
test_results = from(tr in TestResult, where: tr.id in ^test_result_ids, preload: [:events]) |> Repo.all()
index_case_ids = Enum.reduce(test_results, [], fn tr, ic_ids ->
  case Enum.map(tr.events, & &1.data["index_case_id"]) |> Enum.filter(& &1) |> Enum.uniq() do
    [] -> ic_ids
    new_ic_ids -> ic_ids ++ new_ic_ids
  end
end)
# look up the created index case id
index_cases = from(ic in IndexCase, where: ic.id in ^index_case_ids) |> Repo.all()
{ok, error} = index_cases
|> Enum.filter(fn ic ->
  IO.write("C")
  case County.get(fips: ic.county_id) do
    {:ok, _} -> true
    _ ->
      IO.puts("County #{ic.county_id} not found for index case #{ic.id}")
      false
    end
end)
|> Enum.split_with(fn ic ->
  IO.write("I")
  # check commcare for the cases
  {:ok, county} = County.get(fips: ic.county_id)
  Api.get_case(commcare_case_id: ic.case_id, county_domain: county.domain) |> elem(0) == :ok
end)

ok |> Enum.map(& &1.case_id) |> IO.inspect(label: "found cases", limit: :infinity)
error |> Enum.map(& &1.case_id) |> IO.inspect(label: "NOT found cases", limit: :infinity)
