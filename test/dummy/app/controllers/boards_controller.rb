class BoardsController < ApplicationController
  COLUMNS = %w[inbox archive trash].freeze

  def show
    @columns = COLUMNS.index_with do |label|
      current_contact.received_messages.where(label: label).in_board_order
    end
  end
end
