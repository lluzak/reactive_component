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
    using_session(:ana) { claim_card(@message1) }

    using_session(:tom) do
      assert_selector "[data-card-id='#{card_id(@message1)}'][data-presence-busy='#{@bob.name}']", wait: 10
    end
  end

  test 'a card someone else is holding cannot be dragged away' do
    open_board_as(:ana, @bob)
    open_board_as(:tom, @charlie)

    using_session(:tom) { assert_selector '[data-presence-here]', wait: 10 }
    using_session(:ana) { claim_card(@message1) }

    using_session(:tom) do
      assert_selector "[data-card-id='#{card_id(@message1)}'][data-presence-busy]", wait: 10
      drag_card_to(@message1, 'trash')
    end

    assert_equal 'inbox', @message1.reload.label
  end

  test 'a card dropped below another lands after it for everyone' do
    open_board_as(:ana, @bob)
    open_board_as(:tom, @charlie)

    using_session(:tom) { assert_selector '[data-presence-here]', wait: 10 }

    # Drop message1 below message3, both of which start in the inbox.
    using_session(:ana) { drop_card_after(@message1, @message3, 'inbox') }

    using_session(:tom) do
      ids = all("[data-column='inbox'] .card-shell").pluck('data-card-id')

      assert_operator ids.index(card_id(@message1)), :>, ids.index(card_id(@message3)),
                      "expected #{card_id(@message1)} after #{card_id(@message3)} in #{ids.inspect}"
    end

    assert_operator @message1.reload.position, :>, @message3.reload.position
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

  # What `dragstart->presence#claim` does, without holding a drag open.
  def claim_card(message)
    page.execute_script(<<~JS, card_id(message))
      const shell = document.querySelector(`[data-card-id="${arguments[0]}"]`)
      const controller = window.Stimulus.getControllerForElementAndIdentifier(
        shell.closest('[data-controller~="presence"]'), "presence")
      controller.claim({ target: shell })
    JS
  end

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

      board.pick({ currentTarget: shell, preventDefault() {}, dataTransfer: { effectAllowed: "", setData() {} } })
      board.drop({
        preventDefault() {},
        currentTarget: column,
        clientY: 0,
        dataTransfer: { getData: () => arguments[0] }
      })
    JS
  end

  # Drops `message` just below `target`, which is what the pointer being past
  # that card's midpoint means.
  def drop_card_after(message, target, label)
    page.execute_script(<<~JS, card_id(message), card_id(target), label)
      const shell = document.querySelector(`[data-card-id="${arguments[0]}"]`)
      const target = document.querySelector(`[data-card-id="${arguments[1]}"]`)
      const column = document.querySelector(`[data-column="${arguments[2]}"]`)
      const board = window.Stimulus.getControllerForElementAndIdentifier(
        shell.closest('[data-controller~="board"]'), "board")
      const rect = target.getBoundingClientRect()

      board.pick({ currentTarget: shell, preventDefault() {}, dataTransfer: { effectAllowed: "", setData() {} } })
      board.drop({
        preventDefault() {},
        currentTarget: column,
        clientY: rect.top + rect.height * 0.75,
        dataTransfer: { getData: () => arguments[0] }
      })
    JS
  end
end
