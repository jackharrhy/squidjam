defmodule Jahns.GameServer do
  use GenServer

  require Logger

  alias Jahns.Game

  def add_player(slug, player_id, player_name) do
    with {:ok, game, player} <- call_by_slug(slug, {:add_player, player_id, player_name}) do
      Logger.info("Adding player #{player_id} to game #{slug}")
      broadcast_game_updated!(slug, game)
      {:ok, game, player}
    end
  end

  def start_game(slug, player_id) do
    with {:ok, game} <- call_by_slug(slug, {:start_game, player_id}) do
      Logger.info("Starting game #{slug}")
      broadcast_game_updated!(slug, game)
      {:ok, game}
    end
  end

  def attempt_to_end_turn(slug, player_id) do
    with {:ok, game} <- call_by_slug(slug, {:attempt_to_end_turn, player_id}) do
      Logger.info("Ending turn for player #{player_id} in game #{slug}")
      broadcast_game_updated!(slug, game)
      {:ok, game}
    end
  end

  def attempt_to_use_card(slug, player_id, card_id) do
    with {:ok, game} <- call_by_slug(slug, {:attempt_to_use_card, player_id, card_id}) do
      Logger.info("Using card #{card_id} for player #{player_id} in game #{slug}")
      broadcast_game_updated!(slug, game)
      {:ok, game}
    end
  end

  def get_game(slug) do
    call_by_slug(slug, :get_game)
  end

  def get_player_by_id(slug, player_id) do
    call_by_slug(slug, {:get_player_by_id, player_id})
  end

  defp call_by_slug(slug, command) do
    case game_pid(slug) do
      game_pid when is_pid(game_pid) ->
        GenServer.call(game_pid, command)

      nil ->
        {:error, :game_not_found}
    end
  end

  def start_link(slug) do
    GenServer.start(__MODULE__, slug, name: via_tuple(slug))
  end

  def game_pid(slug) do
    slug
    |> via_tuple()
    |> GenServer.whereis()
  end

  def game_exists?(slug) do
    game_pid(slug) != nil
  end

  @impl GenServer
  def init(slug) do
    Logger.info("Creating game server with slug #{slug}")
    {:ok, %{game: Game.new(slug)}}
  end

  @impl GenServer
  def handle_call({:add_player, player_id, player_name}, _from, state) do
    case Game.add_player(state.game, player_id, player_name) do
      {:ok, game, player} ->
        {:reply, {:ok, game, player}, %{state | game: game}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call({:start_game, player_id}, _from, state) do
    case Game.start_game(state.game, player_id) do
      {:ok, game} ->
        {:reply, {:ok, game}, %{state | game: game}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call({:attempt_to_end_turn, player_id}, _from, state) do
    case Game.attempt_to_end_turn(state.game, player_id) do
      {:ok, game, nil} ->
        {:reply, {:ok, game}, %{state | game: game}}

      {:ok, game, {send_after, message}} ->
        :timer.send_after(send_after, self(), message)
        {:reply, {:ok, game}, %{state | game: game}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call({:attempt_to_use_card, player_id, card_id}, _from, state) do
    case Game.attempt_to_use_card(state.game, player_id, card_id) do
      {:ok, game, nil} ->
        {:reply, {:ok, game}, %{state | game: game}}

      {:ok, game, {send_after, message}} ->
        :timer.send_after(send_after, self(), message)

        {:reply, {:ok, game}, %{state | game: game}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call(:get_game, _from, state) do
    {:reply, {:ok, state.game}, state}
  end

  @impl GenServer
  def handle_call({:get_player_by_id, player_id}, _from, state) do
    {:reply, Game.get_player_by_id(state.game, player_id), state}
  end

  @impl GenServer
  def handle_info({:move_active_player, value}, state) do
    Logger.info("Moving active player, #{value} left")

    case Game.move_active_player(state.game, value) do
      {:ok, game, nil} ->
        broadcast_game_updated!(game.slug, game)
        {:noreply, %{state | game: game}}

      {:ok, game, {send_after, message}} ->
        :timer.send_after(send_after, self(), message)
        broadcast_game_updated!(game.slug, game)
        {:noreply, %{state | game: game}}
    end
  end

  @impl GenServer
  def handle_info({:put_game_into_state, game_state}, state) do
    Logger.info("Putting game state from #{inspect(state.game.state)} to #{inspect(game_state)}")
    game = Game.put_game_into_state(state.game, game_state)
    broadcast_game_updated!(game.slug, game)
    {:noreply, %{state | game: game}}
  end

  @impl GenServer
  def handle_info({:restock_and_continue_active_player_pull, remaining}, state) do
    Logger.info("Restocking and continuing active player pull, #{remaining} remaining")

    {:ok, game, {send_after, message}} =
      Game.restock_and_continue_active_player_pull(state.game, remaining)

    :timer.send_after(send_after, self(), message)
    broadcast_game_updated!(game.slug, game)
    {:noreply, %{state | game: game}}
  end

  @impl GenServer
  def handle_info({:pull_from_active_player_draw_pile, remaining}, state) do
    Logger.info("Pulling from active player draw pile, #{remaining} remaining")

    {:ok, game, {send_after, message}} =
      Game.pull_from_active_player_draw_pile(state.game, remaining)

    :timer.send_after(send_after, self(), message)
    broadcast_game_updated!(game.slug, game)
    {:noreply, %{state | game: game}}
  end

  defp broadcast_game_updated!(slug, game) do
    broadcast!(slug, :game_updated, %{game: game})
  end

  def broadcast!(slug, event, payload \\ %{}) do
    Phoenix.PubSub.broadcast!(Jahns.PubSub, slug, %{event: event, payload: payload})
  end

  defp via_tuple(slug) do
    {:via, Registry, {Jahns.GameRegistry, slug}}
  end
end
