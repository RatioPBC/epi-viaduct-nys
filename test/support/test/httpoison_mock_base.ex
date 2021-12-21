defmodule NYSETL.Test.HTTPoisonMockBase do
  defmacro __using__(_) do
    quote location: :keep do
      @impl true
      def delete!(_), do: raise("unimplemented")
      @impl true
      def delete!(_, _), do: raise("unimplemented")
      @impl true
      def delete!(_, _, _), do: raise("unimplemented")
      @impl true
      def delete(_), do: raise("unimplemented")
      @impl true
      def delete(_, _), do: raise("unimplemented")
      @impl true
      def delete(_, _, _), do: raise("unimplemented")
      @impl true
      def get!(_), do: raise("unimplemented")
      @impl true
      def get!(_, _), do: raise("unimplemented")
      @impl true
      def get!(_, _, _), do: raise("unimplemented")
      @impl true
      def get(_), do: raise("unimplemented")
      @impl true
      def get(_, _), do: raise("unimplemented")
      @impl true
      def get(_, _, _), do: raise("unimplemented")
      @impl true
      def head!(_), do: raise("unimplemented")
      @impl true
      def head!(_, _), do: raise("unimplemented")
      @impl true
      def head!(_, _, _), do: raise("unimplemented")
      @impl true
      def head(_), do: raise("unimplemented")
      @impl true
      def head(_, _), do: raise("unimplemented")
      @impl true
      def head(_, _, _), do: raise("unimplemented")
      @impl true
      def options!(_), do: raise("unimplemented")
      @impl true
      def options!(_, _), do: raise("unimplemented")
      @impl true
      def options!(_, _, _), do: raise("unimplemented")
      @impl true
      def options(_), do: raise("unimplemented")
      @impl true
      def options(_, _), do: raise("unimplemented")
      @impl true
      def options(_, _, _), do: raise("unimplemented")
      @impl true
      def patch!(_, _), do: raise("unimplemented")
      @impl true
      def patch!(_, _, _), do: raise("unimplemented")
      @impl true
      def patch!(_, _, _, _), do: raise("unimplemented")
      @impl true
      def patch(_, _), do: raise("unimplemented")
      @impl true
      def patch(_, _, _), do: raise("unimplemented")
      @impl true
      def patch(_, _, _, _), do: raise("unimplemented")
      @impl true
      def post!(_, _), do: raise("unimplemented")
      @impl true
      def post!(_, _, _), do: raise("unimplemented")
      @impl true
      def post!(_, _, _, _), do: raise("unimplemented")
      @impl true
      def post(_, _), do: raise("unimplemented")
      @impl true
      def post(_, _, _), do: raise("unimplemented")
      @impl true
      def post(_, _, _, _), do: raise("unimplemented")
      @impl true
      def process_headers(_), do: raise("unimplemented")
      @impl true
      def process_request_body(_), do: raise("unimplemented")
      @impl true
      def process_request_headers(_), do: raise("unimplemented")
      @impl true
      def process_request_options(_), do: raise("unimplemented")
      @impl true
      def process_request_params(_), do: raise("unimplemented")
      @impl true
      def process_request_url(_), do: raise("unimplemented")
      @impl true
      def process_response(_), do: raise("unimplemented")
      @impl true
      def process_response_body(_), do: raise("unimplemented")
      @impl true
      def process_response_chunk(_), do: raise("unimplemented")
      @impl true
      def process_response_headers(_), do: raise("unimplemented")
      @impl true
      def process_response_status_code(_), do: raise("unimplemented")
      @impl true
      def process_status_code(_), do: raise("unimplemented")
      @impl true
      def process_url(_), do: raise("unimplemented")
      @impl true
      def put!(_), do: raise("unimplemented")
      @impl true
      def put!(_, _), do: raise("unimplemented")
      @impl true
      def put!(_, _, _), do: raise("unimplemented")
      @impl true
      def put!(_, _, _, _), do: raise("unimplemented")
      @impl true
      def put(_), do: raise("unimplemented")
      @impl true
      def put(_, _), do: raise("unimplemented")
      @impl true
      def put(_, _, _), do: raise("unimplemented")
      @impl true
      def put(_, _, _, _), do: raise("unimplemented")
      @impl true
      def request!(_, _), do: raise("unimplemented")
      @impl true
      def request!(_, _, _), do: raise("unimplemented")
      @impl true
      def request!(_, _, _, _), do: raise("unimplemented")
      @impl true
      def request!(_, _, _, _, _), do: raise("unimplemented")
      @impl true
      def request(_), do: raise("unimplemented")
      @impl true
      def request(_, _), do: raise("unimplemented")
      @impl true
      def request(_, _, _), do: raise("unimplemented")
      @impl true
      def request(_, _, _, _), do: raise("unimplemented")
      @impl true
      def request(_, _, _, _, _), do: raise("unimplemented")
      @impl true
      def start(), do: raise("unimplemented")
      @impl true
      def stream_next(_), do: raise("unimplemented")

      defoverridable delete: 3,
                     get: 3,
                     head!: 3,
                     options!: 1,
                     options!: 3,
                     options: 3,
                     patch!: 4,
                     patch: 3,
                     patch: 4,
                     post!: 3,
                     post: 3,
                     post: 4,
                     post!: 4,
                     process_request_body: 1,
                     process_request_headers: 1,
                     process_response_chunk: 1,
                     process_response_headers: 1,
                     put!: 2,
                     request: 4,
                     request!: 4
    end
  end
end
