defmodule Stressgrid.CoordinatorWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use Stressgrid.CoordinatorWeb, :controller` and
  `use Stressgrid.CoordinatorWeb, :live_view`.
  """
  use Stressgrid.CoordinatorWeb, :html

  embed_templates "layouts/*"
end
