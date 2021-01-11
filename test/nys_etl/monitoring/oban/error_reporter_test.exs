defmodule NYSETL.Monitoring.Oban.ErrorReporterTest do
  use NYSETL.DataCase, async: true

  alias NYSETL.Monitoring.Oban.ErrorReporter

  test "the exception handler doesn't crash" do
    :ignored =
      ErrorReporter.handle_event(
        [:oban, :job, :exception],
        %{foo: 1},
        %{args: "1,2,3", error: %ArgumentError{message: "negative"}, stacktrace: stacktrace()},
        0
      )
  end

  test "the circuit trip handler doesn't crash" do
    :ignored =
      ErrorReporter.handle_event(
        [:oban, :circuit, :trip],
        %{foo: 1},
        %{args: "1,2,3", error: %ArgumentError{message: "negative"}, stacktrace: stacktrace()},
        0
      )
  end

  describe "group_noisy_messages" do
    test "when the message is not noisy, it returns the original message and extras" do
      assert ErrorReporter.group_noisy_messages("not noisy", %{}) == {"not noisy", %{}}
    end

    test "please try again later" do
      message = """
      {"error_message": "Sorry, this request could not be processed. Please try again later."}
      """

      assert ErrorReporter.group_noisy_messages(message, %{}) == {"suspected commcare server error/issue", %{message: message}}
    end

    test "500 Error" do
      message = """
      <!DOCTYPE html>\n\n\n<!--[if lt IE 7]><html lang=\"en\" class=\"lt-ie9 lt-ie8 lt-ie7\"><![endif]-->\n
      <!--[if IE 7]><html lang=\"en\" class=\"lt-ie9 lt-ie8\"><![endif]-->\n<!--[if IE 8]><html lang=\"en\"
      class=\"lt-ie9\"><![endif]-->\n<!--[if gt IE 8]><!--><html lang=\"en\"><!--<![endif]-->\n  <head>\n    \n\n    \n
      \n    <title>\n      \n  500 Error\n\n      - \n      CommCare HQ\n    </title>\n\n
      """

      assert ErrorReporter.group_noisy_messages(message, %{}) == {"suspected commcare server error/issue", %{message: message}}
    end

    test "500 Internal Server Error" do
      message = """
      <html>\r\n<head><title>500 Internal Server Error</title></head>\r\n<body>\r\n<center><h1>500 Internal Server Error
      </h1></center>\r\n<hr><center>nginx</center>\r\n</body>\r\n</html>
      """

      assert ErrorReporter.group_noisy_messages(message, %{}) == {"suspected commcare server error/issue", %{message: message}}
    end

    test "Bad Gateway" do
      message = """
      <html>\r\n<head><title>502 Bad Gateway</title></head>\r\n<body>\r\n<center><h1>502 Bad Gateway</h1></center>\r\n
      </body>\r\n</html>
      """

      assert ErrorReporter.group_noisy_messages(message, %{}) == {"suspected commcare server error/issue", %{message: message}}
    end

    test "Commcare under maintenance" do
      message = """
      <html>\n <head>\n  <!--\n  For production environments, it's necessary to have the href start with
      /errors.\n  To do development, change to error_style/<filename>.css\n  -->\n
      <h1>CommCareHQ is currently undergoing maintenance</h1>\n <p class=\"lead\">\n
      We will be back online as soon as possible, please check the\n
      <a class=\"status-link\" href=\"https://status.commcarehq.org/\">status page</a> for more information.\n
      </p>\n</div>\n  </div>\n </div>\n</div>\n</section>\n </body>\n</html>\n
      """

      assert ErrorReporter.group_noisy_messages(message, %{}) == {"suspected commcare server error/issue", %{message: message}}
    end
  end

  def stacktrace() do
    try do
      :erlang.error(:badarg)
    rescue
      ArgumentError -> __STACKTRACE__
    end
  end
end
