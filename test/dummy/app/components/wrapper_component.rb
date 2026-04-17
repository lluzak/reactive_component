# frozen_string_literal: true

# Wrapper that accepts arbitrary HTML attributes via `**options` and splats
# them into `tag.span`. Used to cover the `**@options` keyword-splat path
# through `process_tag_attrs`.
class WrapperComponent < ApplicationComponent
  def initialize(**options)
    @options = options
  end
end
