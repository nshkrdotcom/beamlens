defmodule Beamlens.IntegrationCaseTest do
  use ExUnit.Case, async: true

  describe "build_client_registry/1 with google-ai" do
    setup do
      original_api_key = System.get_env("GOOGLE_API_KEY")
      original_model = System.get_env("BEAMLENS_TEST_MODEL")

      on_exit(fn ->
        if original_api_key,
          do: System.put_env("GOOGLE_API_KEY", original_api_key),
          else: System.delete_env("GOOGLE_API_KEY")

        if original_model,
          do: System.put_env("BEAMLENS_TEST_MODEL", original_model),
          else: System.delete_env("BEAMLENS_TEST_MODEL")
      end)

      :ok
    end

    test "builds google-ai registry when GOOGLE_API_KEY is set" do
      System.put_env("GOOGLE_API_KEY", "test-key")
      System.delete_env("BEAMLENS_TEST_MODEL")

      assert {:ok, registry} = Beamlens.IntegrationCase.build_client_registry("google-ai")
      assert registry.primary == "Gemini"
      assert [client] = registry.clients
      assert client.name == "Gemini"
      assert client.provider == "google-ai"
      assert client.options.model == "gemini-flash-lite-latest"
    end

    test "returns error when GOOGLE_API_KEY not set" do
      System.delete_env("GOOGLE_API_KEY")

      assert {:error, message} = Beamlens.IntegrationCase.build_client_registry("google-ai")
      assert message =~ "GOOGLE_API_KEY not set"
    end

    test "respects BEAMLENS_TEST_MODEL override for google-ai" do
      System.put_env("GOOGLE_API_KEY", "test-key")
      System.put_env("BEAMLENS_TEST_MODEL", "gemini-1.5-pro")

      assert {:ok, registry} = Beamlens.IntegrationCase.build_client_registry("google-ai")
      assert [client] = registry.clients
      assert client.options.model == "gemini-1.5-pro"
    end
  end
end
