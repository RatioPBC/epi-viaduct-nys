defmodule NYSETL.Engines.E1.SQSTaskTest do
  use NYSETL.SimpleCase
  alias NYSETL.Engines.E1.SQSTask

  test "processable?" do
    assert SQSTask.processable?("foo.TXT")
    assert SQSTask.processable?("foo.txt")

    refute SQSTask.processable?("foo.dat")
    refute SQSTask.processable?("foo")
  end
end
