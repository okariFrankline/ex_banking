defmodule ExBanking.Core.Account do
  @moduledoc """
  This module holds a user's bank account
  """

  @enforce_keys [:owner, :currency]
  defstruct current_balance: nil, owner: nil, currency: nil, created_at: nil

  use ExConstructor
  use Vex.Struct

  @type t :: %__MODULE__{
          current_balance: Money.t(),
          owner: String.t(),
          currency: String.t(),
          created_at: DateTime.t()
        }

  @doc """
  Given only the owner, it returns a new Account
  struct with the default values.
  """
  def new(user) when is_binary(user) do
    %__MODULE__{
      owner: user,
      current_balance: Money.new!(:USD, "0.00"),
      currency: "USD",
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Converts an amount to a Money struct based on the currency

  ## Examples
        iex> to_money(amount, currency)
        %Money{}

  """
  @spec to_money(amount :: number(), currency :: String.t()) :: Money.t()
  def to_money(amount, currency) do
    currency
    |> String.to_existing_atom()
    |> Money.new(to_string(amount))
  end

  @doc """
  Given amount and currency, this function returns a money struct
  that is in the same currency as the account being used.

  ## Examples
      iex> convert_to_owner_currency(owner_account, amount, currency)
      %Money{}

  """
  @spec to_owner_currency(owner_account :: t(), amount :: number(), currency :: String.t()) ::
          {:ok, Money.t()}
  def to_owner_currency(%__MODULE__{} = account, amount, currency) do
    amount
    |> to_money(currency)
    |> then(&to_owner_currency(account, &1))
  end

  @doc """
  Changes the given money from one currency to another

  ## Examples
      iex> to_currency(account, currency)
      %Money{}

  """
  @spec to_currency(account :: t(), currency :: String.t()) :: {:ok, Money.t()} | {:error, term()}
  def to_currency(%__MODULE__{current_balance: balance}, currency) do
    currency
    |> String.to_existing_atom()
    |> then(&Money.to_currency(balance, &1))
  end

  @spec to_owner_currency(owner_account :: t(), money_to_change :: Money.t()) :: {:ok, Money.t()}
  defp to_owner_currency(%__MODULE__{current_balance: balance}, %Money{} = money_to_change) do
    balance
    |> Money.to_currency_code()
    |> then(&Money.to_currency(money_to_change, &1))
  end
end
