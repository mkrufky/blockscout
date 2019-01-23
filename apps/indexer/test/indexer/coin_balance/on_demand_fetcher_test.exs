defmodule Indexer.CoinBalance.OnDemandFetcherTest do
  # MUST be `async: false` so that {:shared, pid} is set for connection to allow CoinBalanceFetcher's self-send to have
  # connection allowed immediately.
  use EthereumJSONRPC.Case, async: false
  use Explorer.DataCase

  import Mox

  alias Explorer.Counters.AverageBlockTime
  alias Indexer.CoinBalance.OnDemandFetcher

  @moduletag :capture_log

  # MUST use global mode because we aren't guaranteed to get `start_supervised`'s pid back fast enough to `allow` it to
  # use expectations and stubs from test's pid.
  setup :set_mox_global

  setup :verify_on_exit!

  setup do
    start_supervised!({Task.Supervisor, name: Indexer.TaskSupervisor})
    start_supervised!(AverageBlockTime)

    Application.put_env(:explorer, AverageBlockTime, enabled: true)

    on_exit(fn ->
      Application.put_env(:explorer, AverageBlockTime, enabled: false)
    end)

    :ok
  end

  describe "trigger_fetch/1" do
    setup do
      now = Timex.now()


      # we space these very far apart so that we know it will consider the 0th block stale (it calculates how far
      # back we'd need to go to get 24 hours in the past)
      block_0 = insert(:block, number: 0, timestamp: Timex.shift(now, hours: -50))
      AverageBlockTime.average_block_time(block_0)
      block_1 = insert(:block, number: 1, timestamp: now)
      AverageBlockTime.average_block_time(block_1)

      stale_address = insert(:address, fetched_coin_balance: 1, fetched_coin_balance_block_number: 0)
      current_address = insert(:address, fetched_coin_balance: 1, fetched_coin_balance_block_number: 1)

      pending_address = insert(:address, fetched_coin_balance: 1, fetched_coin_balance_block_number: 1)
      insert(:unfetched_balance, address_hash: pending_address.hash, block_number: 2)

      %{stale_address: stale_address, current_address: current_address, pending_address: pending_address}
    end

    test "treats all addresses as current if the average block time is disabled", %{stale_address: address} do
      Application.put_env(:explorer, AverageBlockTime, enabled: false)

      assert OnDemandFetcher.trigger_fetch(address) == :current
    end

    test "if the address has not been fetched within the last 24 hours of blocks it is considered stale", %{
      stale_address: address
    } do
      assert OnDemandFetcher.trigger_fetch(address) == {:stale, 1}
    end

    test "if the address has been fetched within the last 24 hours of blocks it is considered current", %{
      current_address: address
    } do
      assert OnDemandFetcher.trigger_fetch(address) == :current
    end

    test "if there is an unfetched balance within the window for an address, it is considered pending", %{
      pending_address: pending_address
    } do
      assert OnDemandFetcher.trigger_fetch(pending_address) == {:pending, 2}
    end
  end
end
