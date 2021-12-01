#!/bin/sh

grep_version=$(grep --version)
if [ $? -gt 1 ]; then
  echo "Unsupported version of grep. Use BSD or GNU grep"
  exit 1
fi

set -e

# GNU grep supports -P for perl regexes; other greps use -E
if echo $grep_version | grep -q "GNU grep"; then
  grep_flag="-P"
else
  grep_flag="-E"
fi

expected_elixir=$(cat .tool-versions | grep elixir | grep $grep_flag -o '(\d+\.\d+\.\d+)')
actual_elixir=$(elixir -e "IO.puts(System.version())")

if [ $expected_elixir != $actual_elixir ]; then
  echo "Expected Elixir $expected_elixir, got $actual_elixir"
  exit 1
fi

expected_erlang=$(cat .tool-versions | grep erlang | grep $grep_flag -o '(\d+\.\d+\.\d+)')
actual_erlang=$(erl -eval '{ok, Version} = file:read_file(filename:join([code:root_dir(), "releases", erlang:system_info(otp_release), "OTP_VERSION"])), io:fwrite(Version), halt().' -noshell)

if [ $expected_erlang != $actual_erlang ]; then
  echo "Expected Erlang $expected_erlang, got $actual_erlang"
  exit 1
fi

echo "All expected versions match:"
echo "\tElixir $expected_elixir"
echo "\tErlang $expected_erlang"
