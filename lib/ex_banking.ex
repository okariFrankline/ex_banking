defmodule ExBanking do
  @moduledoc """
  Documentation for `ExBanking`.
  """

  alias ExBanking.Utils.Helpers

  @typep user :: String.t()
  @typep currency :: String.t()
  @typep money :: number()
  @typep reason :: :wrong_arguments | :user_does_not_exist | :too_many_requests_to_user
  @typep send_error_reason ::
           :wrong_arguments
           | :not_enough_money
           | :sender_does_not_exist
           | :receiver_does_not_exist
           | :too_many_requests_to_sender
           | :too_many_requests_to_receiver
  @typep error_reason :: reason() | send_error_reason()

  ## Checks to confirm that all the params for given transactions are valid
  defguardp is_valid_params(user, amount, currency)
            when is_binary(user) and is_number(amount) and is_binary(currency)

  @doc """
  Creates a new user.
  """
  @spec create_user(user :: String.t()) ::
          :ok | {:error, :wrong_arguments} | {:error, :user_exists}
  def create_user(user) when is_binary(user), do: Helpers.do_create_account(user)

  def create_user(_user), do: {:error, :wrong_arguments}

  @doc """
  Deposits moeny into a user's account
  """
  @spec deposit(user :: user(), amount :: money(), currency :: currency()) ::
          {:ok, balance :: money()} | {:error, reason :: error_reason()}
  def deposit(user, amount, currency) when is_valid_params(user, amount, currency),
    do: Helpers.do_transaction(:deposit, user, amount, currency)

  def deposit(_user, _amount, _currency), do: {:error, :wrong_arguments}

  @doc """
  Allows a user to withdraw from his/her account an amount of
  money from whichever valid currency
  """
  @spec withdraw(user :: user(), amount :: money(), currency :: currency()) ::
          {:ok, balance :: money()} | {:error, error_reason()}
  def withdraw(user, amount, currency) when is_valid_params(user, amount, currency),
    do: Helpers.do_transaction(:withdrawal, user, amount, currency)

  def withdraw(_user, _amount, _currency), do: {:error, :wrong_arguments}

  @doc """
  Allows a user to query for their current balance.
  If there are any pending transactions, this will wait for all the
  pending transactions to complete, and then return the balance
  """
  @spec get_balance(user :: String.t(), currency :: String.t()) ::
          {:ok, balance :: number} | {:error, error_reason()}
  def get_balance(user, currency) when is_binary(user) and is_binary(currency),
    do: Helpers.do_get_balance(user, currency)

  def get_balance(_user, _currency), do: {:error, :wrong_arguments}

  @doc """
  Allows a user to send money to to another user.
  """
  def send(from_user, to_user, amount, currency)
      when is_valid_params(from_user, amount, currency) and is_binary(to_user),
      do: Helpers.do_send_transaction(from_user, to_user, amount, currency)

  def send(_from_user, _to_user, _amount, _currency), do: {:error, :wrong_arguments}
end
