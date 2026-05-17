defmodule GlobalPayrollWeb.Helpers do
  def format_money(nil), do: "$0.00"
  def format_money(value) do
    d = Decimal.new(value) |> Decimal.round(2)
    str = Decimal.to_string(d, :normal)

    {sign, abs_str} =
      if String.starts_with?(str, "-"),
        do: {"-", String.slice(str, 1..-1//1)},
        else: {"", str}

    [int_part, dec_part] =
      case String.split(abs_str, ".") do
        [i, d] -> [i, String.pad_trailing(d, 2, "0")]
        [i] -> [i, "00"]
      end

    formatted_int =
      int_part
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.chunk_every(3)
      |> Enum.map(&Enum.join/1)
      |> Enum.join(",")
      |> String.graphemes()
      |> Enum.reverse()
      |> Enum.join()

    "$#{sign}#{formatted_int}.#{dec_part}"
  end

  def format_number(value) when is_integer(value) do
    value
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.join/1)
    |> Enum.join(",")
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.join()
  end
end
