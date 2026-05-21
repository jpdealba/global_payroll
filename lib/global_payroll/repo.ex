defmodule GlobalPayroll.Repo do
  use Ecto.Repo,
    otp_app: :global_payroll,
    adapter: Ecto.Adapters.Postgres
end
