# frozen_string_literal: true

module ReactiveComponent
  # Helpers a component's template can call on either render path: the server
  # render that produces the page, and the compiled template that produces an
  # update.
  module TemplateHelpers
    # Server-rendered HTML that cannot differ between two renders of this
    # template — an icon, a static fragment. The compiler evaluates it once and
    # keeps it in the compiled template, so it never rides a payload. On the
    # server it is already the HTML it stands for.
    def const(html) = html
  end
end
