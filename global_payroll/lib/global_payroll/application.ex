defmodule GlobalPayroll.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    ExAws.SQS.create_queue("payroll-jobs") |> ExAws.request()
    ExAws.SQS.create_queue("payment-results") |> ExAws.request()

    children = [
      GlobalPayrollWeb.Telemetry,
      GlobalPayroll.Repo,
      {DNSCluster, query: Application.get_env(:global_payroll, :dns_cluster_query) || :ignore},
      GlobalPayroll.Workers.PayrollWorker,
      GlobalPayroll.Workers.PaymentResultsWorker,
      GlobalPayroll.Workers.InvoiceWorker,
      GlobalPayrollWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GlobalPayroll.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GlobalPayrollWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
