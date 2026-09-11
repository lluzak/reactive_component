# frozen_string_literal: true

require 'system_test_helper'

class BoardTest < SystemTestCase
  test 'a card dragged to another column moves for everyone' do
    open_board_as(:ana, @bob)
    open_board_as(:tom, @charlie)

    using_session(:tom) { assert_selector '[data-presence-here]', wait: 10 }

    using_session(:ana) { drag_card_to(@message1, 'archive') }

    using_session(:tom) do
      assert_selector "[data-column='archive'] [data-card-id='#{card_id(@message1)}']", wait: 10
    end

    assert_equal 'archive', @message1.reload.label
  end

  test 'a card someone else is dragging is marked as held' do
    open_board_as(:ana, @bob)
    open_board_as(:tom, @charlie)

    using_session(:tom) { assert_selector '[data-presence-here]', wait: 10 }

    # A real dragstart is hard to hold open across sessions, so claim the card
    # the way the drag action does and leave it claimed.
    using_session(:ana) do
      page.execute_script(<<~JS, card_id(@message1))
        const shell = document.querySelector(`[data-card-id="${arguments[0]}"]`)
        const controller = window.Stimulus.getControllerForElementAndIdentifier(
          shell.closest('[data-controller~="presence"]'), "presence")
        controller.claim({ target: shell })
      JS
    end

    using_session(:tom) do
      assert_selector "[data-card-id='#{card_id(@message1)}'][data-presence-busy='#{@bob.name}']", wait: 10
    end
  end

  test 'the board renders every column' do
    open_board_as(:ana, @bob)

    using_session(:ana) do
      assert_selector "[data-column='inbox']"
      assert_selector "[data-column='archive']"
      assert_selector "[data-column='trash']"
      assert_selector '.card-shell', minimum: 1
    end
  end

  private

  def card_id(message)
    ActionView::RecordIdentifier.dom_id(message, :card)
  end

  def open_board_as(session, viewer)
    using_session(session) do
      visit "/board?as=#{viewer.id}"
      wait_for_action_cable

      assert_selector '.card-shell', minimum: 1
    end
  end

  # Cuprite has no native drag, and HTML5 drag events cannot be synthesised
  # with a plain click, so drive the same handlers the browser would.
  def drag_card_to(message, label)
    page.execute_script(<<~JS, card_id(message), label)
      const shell = document.querySelector(`[data-card-id="${arguments[0]}"]`)
      const column = document.querySelector(`[data-column="${arguments[1]}"]`)
      const board = window.Stimulus.getControllerForElementAndIdentifier(
        shell.closest('[data-controller~="board"]'), "board")

      board.pick({ currentTarget: shell, dataTransfer: { effectAllowed: "", setData() {} } })
      board.drop({
        preventDefault() {},
        currentTarget: column,
        dataTransfer: { getData: () => arguments[0] }
      })
    JS
  end
end
