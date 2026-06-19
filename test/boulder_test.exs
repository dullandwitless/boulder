defmodule BoulderTest do
  use ExUnit.Case
  alias Boulder.SyslogGenerator

  test "generates valid RFC 5424 messages" do
    msg = SyslogGenerator.generate(rfc: :rfc5424, hostname: "test-host", severity: 3, facility: 4)
    
    # Priority for sev=3, fac=4 is (4 * 8) + 3 = 35
    assert String.starts_with?(msg, "<35>1 ")
    assert msg =~ "test-host"
    assert msg =~ " - "
  end

  test "generates valid RFC 3164 messages" do
    msg = SyslogGenerator.generate(rfc: :rfc3164, hostname: "legacy-host", severity: 6, facility: 16)
    
    # Priority for sev=6, fac=16 is (16 * 8) + 6 = 134
    assert String.starts_with?(msg, "<134>")
    assert msg =~ "legacy-host"
  end

  test "random generator options fall back to defaults" do
    msg_5424 = SyslogGenerator.generate(rfc: :rfc5424)
    assert msg_5424 =~ "<"
    assert msg_5424 =~ " "

    msg_3164 = SyslogGenerator.generate(rfc: :rfc3164)
    assert msg_3164 =~ "<"
    assert msg_3164 =~ ":"
  end
end
