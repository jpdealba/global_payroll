defmodule GlobalPayrollWeb.Router do
  use GlobalPayrollWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", GlobalPayrollWeb do
    pipe_through :api

    resources "/companies", CompanyController, only: [:index, :create, :update]

    get "/employees", EmployeeController, :index
    post "/employees", EmployeeController, :create
    put "/employees/:id", EmployeeController, :update

    get "/payroll-runs", PayrollRunController, :index
    post "/payroll-runs", PayrollRunController, :create
    get "/payroll-runs/:id", PayrollRunController, :show
    post "/payroll-runs/:id/start", PayrollRunController, :start
    post "/payroll-runs/:id/approve", PayrollRunController, :approve
    post "/payroll-runs/:id/cancel", PayrollRunController, :cancel
    get "/payroll-runs/:id/intents", PayrollRunController, :list_intents
    get "/payroll-runs/:id/payslips", PayrollRunController, :list_payslips
    get "/employees/:id/payslips", EmployeeController, :list_payslips
    get "/companies/:id/invoices", CompanyController, :list_invoices

    get "/country-tax-rules", CountryTaxRuleController, :index
    put "/country-tax-rules/:id", CountryTaxRuleController, :update

    get "/payment-methods", PaymentMethodController, :index
    post "/payment-methods", PaymentMethodController, :create
    put "/payment-methods/:id", PaymentMethodController, :update
    delete "/payment-methods/:id", PaymentMethodController, :delete

    get "/companies/:company_id/transactions", CompanyTransactionController, :index
    post "/companies/:company_id/deposit", CompanyTransactionController, :deposit
  end

  scope "/webhooks", GlobalPayrollWeb do
    pipe_through :api
    post "/payment-provider", PaymentWebhookController, :event
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:global_payroll, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: GlobalPayrollWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end

  end
end
