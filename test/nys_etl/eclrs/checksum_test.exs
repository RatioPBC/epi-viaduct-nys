defmodule NYSETL.ECLRS.ChecksumTest do
  use NYSETL.DataCase, async: true

  alias NYSETL.ECLRS.File
  alias NYSETL.ECLRS.Checksum

  describe "checksum" do
    setup do
      [
        v1_row_1: "LASTNAME||FIRSTNAME|01MAR1947:00:00:00.000000|M|123 MAIN St||||1111|(555) 123-4567|3130|31D0652945|ACME LABORATORIES INC|15200000000000|321 Main Street||New Rochelle||NEW YORK STATE||321 Main Street|New Rochelle||Sally|Testuser|18MAR2020:00:00:00.000000|20MAR2020:06:03:36.589000|TH68-0|COVID-19 Nasopharynx|94309-2|2019-nCoV RNA XXX NAA+probe-Imp|19MAR2020:19:20:00.000000|Positive for 2019-nCoV|Positive for 2019-nCoV|F||10828004|Positive for 2019-nCoV|102695116|19MAR2020:19:20:00.000000|NASOPHARYNX|15200070260000|14MAY2020:13:43:16.000000|POSITIVE",
        v1_row_2: "SMITH||AGENT|01JAN1970:00:00:00.000000|M|456 OTHER ST|APT 1||00000|9999|5551234568|1067|33D0654341|WADSWORTH|15200000000001|321 MAIN STREET|PO BOX 1234|SPRINGFIELD||ACME MEDICAL CENTER|1112223333|321 MAIN STREET|SPRINGFIELD|PFI2128-LABDIR|BOBBY, MD|TESTUSER|21MAR2020:19:24:00.000000|22MAR2020:07:40:38.855000|49365|2019 nCoV Real-Time RT-PCR|94309-2|2019-nCoV N XXX Ql NAA N2|21MAR2020:19:24:00.000000|Positive (qualifier value)|Positive (qualifier value)|F|Acme Center|260373001|Positive (qualifier value)|IDR2000016257-01|19MAR2020:19:20:00.000000|Swab from nasal sinus|15200070260001|30APR2020:14:53:52.000000|POSITIVE",
        v1_row_3: "GOODE|B|JOHNNY|02JAN1972:00:00:00.000000|M|789 ANOTHER ST|APT 2||00000|9999|5551234568|1067|33D0654341|WADSWORTH|15200000000002|321 MAIN STREET|PO BOX 1234|SPRINGFIELD||ACME MEDICAL CENTER|1112223333|321 MAIN STREET|SPRINGFIELD|PFI2128-LABDIR|BOBBY, MD|TESTUSER|21MAR2020:19:24:00.000000|22MAR2020:07:40:38.855000|49365|2019 nCoV Real-Time RT-PCR|94309-2|2019-nCoV N XXX Ql NAA N2|21MAR2020:19:24:00.000000|Positive (qualifier value)|Positive (qualifier value)|F|Acme Center|260373001|Positive (qualifier value)|IDR2000016257-02|19MAR2020:19:20:00.000000|Swab from nasal sinus|15200070260002|30APR2020:14:53:52.000000|POSITIVE",
        v1_file: %File{eclrs_version: 1},
        v2_row_1: "LASTNAME||FIRSTNAME|01MAR1947:00:00:00.000000|M|123 MAIN St||||1111|(555) 123-4567|3130|31D0652945|ACME LABORATORIES INC|15200000000000|321 Main Street||New Rochelle||NEW YORK STATE||321 Main Street|New Rochelle||Sally|Testuser|18MAR2020:00:00:00.000000|20MAR2020:06:03:36.589000|TH68-0|COVID-19 Nasopharynx|94309-2|2019-nCoV RNA XXX NAA+probe-Imp|19MAR2020:19:20:00.000000|Positive for 2019-nCoV|Positive for 2019-nCoV|F||10828004|Positive for 2019-nCoV|102695116|19MAR2020:19:20:00.000000|NASOPHARYNX|15200070260000|14MAY2020:13:43:16.000000||||||||||||POSITIVE",
        v2_row_2: "SMITH||AGENT|01JAN1970:00:00:00.000000|M|456 OTHER ST|APT 1||00000|9999|5551234568|1067|33D0654341|WADSWORTH|15200000000001|321 MAIN STREET|PO BOX 1234|SPRINGFIELD||ACME MEDICAL CENTER|1112223333|321 MAIN STREET|SPRINGFIELD|PFI2128-LABDIR|BOBBY, MD|TESTUSER|21MAR2020:19:24:00.000000|22MAR2020:07:40:38.855000|49365|2019 nCoV Real-Time RT-PCR|94309-2|2019-nCoV N XXX Ql NAA N2|21MAR2020:19:24:00.000000|Positive (qualifier value)|Positive (qualifier value)|F|Acme Center|260373001|Positive (qualifier value)|IDR2000016257-01|19MAR2020:19:20:00.000000|Swab from nasal sinus|15200070260001|30APR2020:14:53:52.000000|Employer Name|Employer Address|Employer Phone|Employer Phone Alt|Employee Number|Employee Job Title|School Name|School District|School Code|School Job Class|School Present|POSITIVE",
        v2_row_3: "GOODE|B|JOHNNY|02JAN1972:00:00:00.000000|M|789 ANOTHER ST|APT 2||00000|9999|5551234568|1067|33D0654341|WADSWORTH|15200000000002|321 MAIN STREET|PO BOX 1234|SPRINGFIELD||ACME MEDICAL CENTER|1112223333|321 MAIN STREET|SPRINGFIELD|PFI2128-LABDIR|BOBBY, MD|TESTUSER|21MAR2020:19:24:00.000000|22MAR2020:07:40:38.855000|49365|2019 nCoV Real-Time RT-PCR|94309-2|2019-nCoV N XXX Ql NAA N2|21MAR2020:19:24:00.000000|Positive (qualifier value)|Positive (qualifier value)|F|Acme Center|260373001|Positive (qualifier value)|IDR2000016257-02|19MAR2020:19:20:00.000000|Swab from nasal sinus|15200070260002|30APR2020:14:53:52.000000||||||||||||POSITIVE",
        v2_file: %File{eclrs_version: 2},
        v3_row_1: "LASTNAME||FIRSTNAME|01MAR1947:00:00:00.000000|M|123 MAIN St||||1111|(555) 123-4567|3130|31D0652945|ACME LABORATORIES INC|15200000000000|321 Main Street||New Rochelle||NEW YORK STATE||321 Main Street|New Rochelle||Sally|Testuser|18MAR2020:00:00:00.000000|20MAR2020:06:03:36.589000|TH68-0|COVID-19 Nasopharynx|94309-2|2019-nCoV RNA XXX NAA+probe-Imp|19MAR2020:19:20:00.000000|Positive for 2019-nCoV|Positive for 2019-nCoV|F||10828004|Positive for 2019-nCoV|102695116|19MAR2020:19:20:00.000000|NASOPHARYNX|15200070260000|14MAY2020:13:43:16.000000|||||||||||||||||||||POSITIVE",
        v3_row_2: "SMITH||AGENT|01JAN1970:00:00:00.000000|M|456 OTHER ST|APT 1||00000|9999|5551234568|1067|33D0654341|WADSWORTH|15200000000001|321 MAIN STREET|PO BOX 1234|SPRINGFIELD||ACME MEDICAL CENTER|1112223333|321 MAIN STREET|SPRINGFIELD|PFI2128-LABDIR|BOBBY, MD|TESTUSER|21MAR2020:19:24:00.000000|22MAR2020:07:40:38.855000|49365|2019 nCoV Real-Time RT-PCR|94309-2|2019-nCoV N XXX Ql NAA N2|21MAR2020:19:24:00.000000|Positive (qualifier value)|Positive (qualifier value)|F|Acme Center|260373001|Positive (qualifier value)|IDR2000016257-01|19MAR2020:19:20:00.000000|Swab from nasal sinus|15200070260001|30APR2020:14:53:52.000000|Employer Name|Employer Address|Employer Phone|Employer Phone Alt|Employee Number|Employee Job Title|School Name|School District|School Code|School Job Class|School Present||||||||||POSITIVE",
        v3_row_3: "GOODE|B|JOHNNY|02JAN1972:00:00:00.000000|M|789 ANOTHER ST|APT 2||00000|9999|5551234568|1067|33D0654341|WADSWORTH|15200000000002|321 MAIN STREET|PO BOX 1234|SPRINGFIELD||ACME MEDICAL CENTER|1112223333|321 MAIN STREET|SPRINGFIELD|PFI2128-LABDIR|BOBBY, MD|TESTUSER|21MAR2020:19:24:00.000000|22MAR2020:07:40:38.855000|49365|2019 nCoV Real-Time RT-PCR|94309-2|2019-nCoV N XXX Ql NAA N2|21MAR2020:19:24:00.000000|Positive (qualifier value)|Positive (qualifier value)|F|Acme Center|260373001|Positive (qualifier value)|IDR2000016257-02|19MAR2020:19:20:00.000000|Swab from nasal sinus|15200070260002|30APR2020:14:53:52.000000||||||||||||Y|20MAR2020:06:03:36.589000|Y|Y|20MAR2020:06:03:36.589000|Y|N|N|N|POSITIVE",
        v3_file: %File{eclrs_version: 3}
      ]
    end

    test "calculates v1 checksum for v1 rows", context do
      assert Checksum.checksum(context.v1_row_1, context.v1_file, :v1) == "YR9Edwh3ctCL7jQnQrjOth98H8njxX+tXxbRm+arnn8="
      assert Checksum.checksum(context.v1_row_2, context.v1_file, :v1) == "2xyXS0QBcixEPmPI2IcHZUyr2OIuSLGhHTdzA0noM/I="
      assert Checksum.checksum(context.v1_row_3, context.v1_file, :v1) == "k68TeJakzpNDZupxeo0FrjJ3X5DT04ssjUfijnmM5rE="
    end

    test "calculates v1 checksum for v2 rows", context do
      assert Checksum.checksum(context.v2_row_1, context.v2_file, :v1) == "YR9Edwh3ctCL7jQnQrjOth98H8njxX+tXxbRm+arnn8="
      assert Checksum.checksum(context.v2_row_2, context.v2_file, :v1) == "2xyXS0QBcixEPmPI2IcHZUyr2OIuSLGhHTdzA0noM/I="
      assert Checksum.checksum(context.v2_row_3, context.v2_file, :v1) == "k68TeJakzpNDZupxeo0FrjJ3X5DT04ssjUfijnmM5rE="
    end

    test "calculates v1 checksum for v3 rows", context do
      assert Checksum.checksum(context.v3_row_1, context.v3_file, :v1) == "YR9Edwh3ctCL7jQnQrjOth98H8njxX+tXxbRm+arnn8="
      assert Checksum.checksum(context.v3_row_2, context.v3_file, :v1) == "2xyXS0QBcixEPmPI2IcHZUyr2OIuSLGhHTdzA0noM/I="
      assert Checksum.checksum(context.v3_row_3, context.v3_file, :v1) == "k68TeJakzpNDZupxeo0FrjJ3X5DT04ssjUfijnmM5rE="
    end

    test "calculates v2 checksum for v1 rows", context do
      assert Checksum.checksum(context.v1_row_1, context.v1_file, :v2) == "c4AeQ4s/s7By9VwwvztlzAiqaXk5IVt8G+4H2URT32U="
      assert Checksum.checksum(context.v1_row_2, context.v1_file, :v2) == "DEVIgFpICrIlCFq7yZprPNSqKeuIXM5slqm4VoxT7+U="
      assert Checksum.checksum(context.v1_row_3, context.v1_file, :v2) == "cVhURpBsRsOm4hVE0c45V8jr7INuCWkqX3GxAR8ldkk="
    end

    test "calculates v2 checksum for v2 rows", context do
      assert Checksum.checksum(context.v2_row_1, context.v2_file, :v2) == "c4AeQ4s/s7By9VwwvztlzAiqaXk5IVt8G+4H2URT32U="
      assert Checksum.checksum(context.v2_row_2, context.v2_file, :v2) == "hk52rV6eghiXb3+9L9DC0/h9vR2Wgt5sZJu+Z4D7EVY="
      assert Checksum.checksum(context.v2_row_3, context.v2_file, :v2) == "cVhURpBsRsOm4hVE0c45V8jr7INuCWkqX3GxAR8ldkk="
    end

    test "calculates v2 checksum for v3 rows", context do
      assert Checksum.checksum(context.v3_row_1, context.v3_file, :v2) == "c4AeQ4s/s7By9VwwvztlzAiqaXk5IVt8G+4H2URT32U="
      assert Checksum.checksum(context.v3_row_2, context.v3_file, :v2) == "hk52rV6eghiXb3+9L9DC0/h9vR2Wgt5sZJu+Z4D7EVY="
      assert Checksum.checksum(context.v3_row_3, context.v3_file, :v2) == "cVhURpBsRsOm4hVE0c45V8jr7INuCWkqX3GxAR8ldkk="
    end

    test "calculates v3 checksum for v1 rows", context do
      assert Checksum.checksum(context.v1_row_1, context.v1_file, :v3) == "RTUA3m3vajNkf9VHtXDIEkK/WZRmH5y1qizhGDx2l/4="
      assert Checksum.checksum(context.v1_row_2, context.v1_file, :v3) == "RdcbYg0gWgHS56YNHxkKDIL1u737MUI2VPNMCXrXcRk="
      assert Checksum.checksum(context.v1_row_3, context.v1_file, :v3) == "Vc0JGTOi9LC5qJ+4bTuq4oW76IDd2wWqNhu+rU+s++A="
    end

    test "calculates v3 checksum for v2 rows", context do
      assert Checksum.checksum(context.v2_row_1, context.v2_file, :v3) == "RTUA3m3vajNkf9VHtXDIEkK/WZRmH5y1qizhGDx2l/4="
      assert Checksum.checksum(context.v2_row_2, context.v2_file, :v3) == "VGWpa4/LeQ+wvWzFMAhd1y15msKC/Z83P7wiuU/1pJQ="
      assert Checksum.checksum(context.v2_row_3, context.v2_file, :v3) == "Vc0JGTOi9LC5qJ+4bTuq4oW76IDd2wWqNhu+rU+s++A="
    end

    test "calculates v3 checksum for v3 rows", context do
      assert Checksum.checksum(context.v3_row_1, context.v3_file, :v3) == "RTUA3m3vajNkf9VHtXDIEkK/WZRmH5y1qizhGDx2l/4="
      assert Checksum.checksum(context.v3_row_2, context.v3_file, :v3) == "VGWpa4/LeQ+wvWzFMAhd1y15msKC/Z83P7wiuU/1pJQ="
      assert Checksum.checksum(context.v3_row_3, context.v3_file, :v3) == "gIOufiQJTrcMF3dDGhtIh2I5cFr7eQmd18GrpRPvcjs="
    end
  end
end
