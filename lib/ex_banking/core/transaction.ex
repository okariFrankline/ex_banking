defmodule ExBanking.Core.Transaction do
  @moduledoc """
  This module stores a record of each of the transaction for a given
  bank account
  """
  alias ExBanking.Core.{Account}

  @enforce_keys [:amount, :type]
  defstruct amount: nil, type: nil

  @typep type :: :deposit | :withdrawal

  @type t :: %__MODULE__{
          amount: Money.t(),
          type: type()
        }

  @doc """
  Creates a new transaction given a map of params
  """
  def new(%{type: type, amount: amount} = _params) do
    %__MODULE__{
      amount: amount,
      type: type
    }
  end

  defguardp is_valid(type) when type == :deposit or type == :withdrawal

  @doc """
  Creates a transaction for the user
  This will contain the correct amount based on the
  currency of the user's account
  """
  def for_user(%{type: type, currency: currency, account: acc, amount: amount})
      when is_atom(type) and is_valid(type) do
    new(%{type: type, amount: Account.to_owner_currency(acc, amount, currency)})
  end
end
