defmodule ExSeq.CLEFEventTest do
  use ExUnit.Case, async: true

  alias ExSeq.CLEFEvent

  defmodule NotEncodable do
    defstruct [:value]
  end

  defp encode(event), do: event |> Jason.encode!() |> Jason.decode!()

  test "maps struct fields to CLEF keys" do
    event = %CLEFEvent{
      level: :Warning,
      timestamp: ~U[2025-01-02 03:04:05.123456Z],
      message: "hello",
      exception: "boom"
    }

    assert encode(event) == %{
             "@t" => "2025-01-02T03:04:05.123456Z",
             "@m" => "hello",
             "@x" => "boom",
             "@l" => "Warning"
           }
  end

  test "strips nil and empty values" do
    event = %CLEFEvent{level: :Information, message: "", properties: [request_id: nil]}

    assert encode(event) == %{"@l" => "Information"}
  end

  test "merges properties into the top level" do
    event = %CLEFEvent{level: :Information, properties: [foo: "bar", list: ["a", "b"]]}

    assert %{"foo" => "bar", "list" => ["a", "b"]} = encode(event)
  end

  test "keeps numbers, booleans and nil" do
    event = %CLEFEvent{
      level: :Information,
      properties: [user_id: 123, ratio: 0.5, admin: false, nested: %{a: nil, b: [1, true]}]
    }

    assert %{
             "user_id" => 123,
             "ratio" => 0.5,
             "admin" => false,
             "nested" => %{"a" => nil, "b" => [1, true]}
           } = encode(event)
  end

  test "converts values JSON can't represent" do
    event = %CLEFEvent{
      level: :Information,
      properties: [
        module: String,
        tuple: {:a, 1},
        pid: self(),
        struct: %NotEncodable{value: 1},
        nested: %{tuple: {:b, 2}}
      ]
    }

    encoded = encode(event)
    assert encoded["module"] == "Elixir.String"
    assert encoded["tuple"] == "{:a, 1}"
    assert encoded["pid"] == inspect(self())
    assert encoded["struct"] == inspect(%NotEncodable{value: 1})
    assert encoded["nested"] == %{"tuple" => "{:b, 2}"}
  end

  test "converts invalid UTF-8, improper lists and bad keys" do
    event = %CLEFEvent{
      level: :Information,
      message: <<"bad ", 255>>,
      properties: [
        binary: <<255>>,
        improper: [1 | 2],
        map: %{{:a, 1} => "tuple key", <<255>> => "binary key", 1 => "number key"}
      ]
    }

    encoded = encode(event)
    assert encoded["@m"] == inspect(<<"bad ", 255>>)
    assert encoded["binary"] == "<<255>>"
    assert encoded["improper"] == "[1 | 2]"

    assert encoded["map"] == %{
             "{:a, 1}" => "tuple key",
             "<<255>>" => "binary key",
             "1" => "number key"
           }
  end

  test "keeps structs that implement Jason.Encoder" do
    event = %CLEFEvent{level: :Information, properties: [date: ~D[2025-01-02]]}

    assert encode(event)["date"] == "2025-01-02"
  end
end
