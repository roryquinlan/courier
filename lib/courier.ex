defmodule Courier do
  use GenServer
  @moduledoc """
  This module is `use`ed by your custom mailer.

  ## Example:

      defmodule MyApp.Mailer do
        use Courier, otp_app: :my_app
      end
  """
  defmacro __using__(opts) do
    {_otp_app, adapter, config} = parse_config(__CALLER__.module, opts)

    quote do
      use Supervisor
      import Courier

      def start_link() do
        unquote(__MODULE__).start_link(__MODULE__, unquote(Macro.escape(config)))
      end

      def deliver(%Mail.Message{} = message, opts \\ []) do
        opts =
          Keyword.merge(unquote(Macro.escape(config)), opts)
          |> Keyword.merge([adapter: __adapter__, mailer: __MODULE__])

        message
        |> Mail.Message.put_header(:date, :calendar.universal_time())
        |> Courier.Scheduler.deliver(opts)
      end

      def init(_), do: :ok

      def __adapter__(),
        do: unquote(Macro.escape(adapter))
    end
  end

  def start_link(mailer, config) do
    Supervisor.start_link(__MODULE__, [mailer, config])
  end

  def init([mailer, config]) do
    import Supervisor.Spec

    adapter = mailer.__adapter__

    adapter.children(config)
    |> supervise(strategy: :one_for_all)
  end

  @doc false
  def parse_config(mailer, opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    config = Application.get_env(otp_app, mailer, [])
    adapter = config[:adapter]

    {otp_app, adapter, config}
  end

  @doc """
  View rendering for mail parts

  Based upon the `template` extension the mail will have the proper `content-type` added.
  For example with the following:

      Courier.render(mail, MailerView, "user.html")

  `Courier` will use `Mail.put_html/2` once it has rendered the template.
  """
  def render(%Mail.Message{} = message, view, template, assigns \\ []) do
    body =
      view.render(template, assigns)
      |> case do
        {:safe, iodata} -> IO.iodata_to_binary(iodata)
        body when is_binary(body) -> body
      end

    case Path.extname(template) do
      ".html" -> Mail.put_html(message, body)
      ".txt" -> Mail.put_text(message, body)
    end
  end
end
