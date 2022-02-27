defmodule ExBanking.Core.Repo do
  @moduledoc """
  Provides all the functions required to interact with the ets table
  """

  alias ExBanking.Core.{Account, Transaction}
  @repo :repo

  @typep account_key :: String.t()
  @typep account :: {account_key(), Account.t()}

  @doc """
  Inserts a new bank account to the repo

  ## Examples
      iex> insert_account({key, %Account{}})
      {:ok, %Account{}}

      iex> insert_account({existing_key, %Account{}})
      {:error, :user_account_exists}

  """
  @spec insert_account(account :: account()) ::
          {:ok, Account.t()} | {:error, :user_exists}
  def insert_account({key, _account} = account) do
    case :ets.insert_new(@repo, account) do
      true ->
        {:ok, get_account!(key)}

      false ->
        {:error, :user_exists}
    end
  end

  ## gets the bank account by the given key
  defp get_account!(key) do
    case :ets.lookup(@repo, key) do
      [{^key, %Account{} = account}] -> account
      [] -> raise_not_found_error(key)
    end
  end

  defp raise_not_found_error(key) do
    message = """
    Expected to find bank account with key #{inspect(key)}
    Instead found #{inspect(nil)}
    """

    raise(message)
  end

  @doc """
  Returns the details about an account identified by a given key

  ## Examples
      iex> get_account(existing_key)
      %Account{}

      iex> get_account(non_existing_key)
      nil

  """
  @spec get_account(key :: account_key()) :: Account.t() | nil
  def get_account(key) do
    case :ets.lookup(@repo, key) do
      [{^key, %Account{} = account}] -> account
      [] -> nil
    end
  end

  @doc """
  Returns true or false if an account exists

  ## Examples
      iex> account_exists?(user)
      true | false

  """
  @spec account_exists?(key :: account_key()) :: true | false
  def account_exists?(key), do: !is_nil(get_account(key))

  @doc """
  Updates the account of a user based on the transaction

  ## Examples
      iex> update_account(key, transaction)
      {:ok, %Account{}}

      iex> update_account(non_existent_key, transaction)
      {:error, :account_not_found}
  """
  @spec update_account(key :: account_key(), transaction :: Transaction.t()) ::
          {:ok, Account.t()} | {:error, :account_not_found}
  def update_account(key, %Transaction{type: :deposit} = transaction) do
    case get_account(key) do
      %Account{} = account ->
        do_account_deposit(account, transaction)

      nil ->
        {:error, :account_not_found}
    end
  end

  def update_account(key, %Transaction{type: :withdrawal} = transaction) do
    case get_account(key) do
      %Account{} = account ->
        do_account_withdrawal(account, transaction)

      nil ->
        {:error, :account_not_found}
    end
  end

  # performs a deposit update
  defp do_account_deposit(%Account{current_balance: balance} = account, %Transaction{
         amount: amount
       }) do
    account
    |> Map.update(:amount, balance, &(&1 + amount))
    |> update_account()
  end

  # performs a withdrawal update
  defp do_account_withdrawal(%Account{current_balance: balance} = account, %Transaction{
         amount: amount
       }) do
    if can_withdraw?(balance, amount) do
      account
      |> Map.update(:amount, balance, &(&1 - amount))
      |> update_account()
    else
      {:error, :insufficient_balance}
    end
  end

  # inserts the new value to the db
  defp update_account(%{owner: owner} = account), do: true = :ets.insert(@repo, {owner, account})

  # check if the current balance is more or equal to amount being withdrawn
  defp can_withdraw?(current_balance, to_withdraw), do: current_balance >= to_withdraw
end
