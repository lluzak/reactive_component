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
    using_session(:ana) { drag_card_to(@message1, 'inbox', hold: true) }

    using_session(:tom) do
      assert_selector "[data-card-id='#{card_id(@message1)}'][data-presence-busy='#{@bob.name}']", wait: 10
    end

    using_session(:ana) { release_card(@message1) }
  end

  test 'a card someone else is holding cannot be dragged away' do
    open_board_as(:ana, @bob)
    open_board_as(:tom, @charlie)

    using_session(:tom) { assert_selector '[data-presence-here]', wait: 10 }
    using_session(:ana) { drag_card_to(@message1, 'inbox', hold: true) }

    using_session(:tom) do
      assert_selector "[data-card-id='#{card_id(@message1)}'][data-presence-busy]", wait: 10
      drag_card_to(@message1, 'trash')
    end

    assert_equal 'inbox', @message1.reload.label
    using_session(:ana) { release_card(@message1) }
  end

  test 'a card dropped below another lands after it for everyone' do
    open_board_as(:ana, @bob)
    open_board_as(:tom, @charlie)

    using_session(:tom) { assert_selector '[data-presence-here]', wait: 10 }

    # The seed order is newest first, so message3 already sits above message1.
    # Reversing that is the only assertion worth making.
    before = using_session(:tom) { inbox_order }

    assert_operator before.index(card_id(@message3)), :<, before.index(card_id(@message1)),
                    'seed order changed; this test no longer reverses anything'

    using_session(:ana) { drop_card_after(@message3, @message1, 'inbox') }

    using_session(:tom) do
      assert_selector "[data-column='inbox'] .card-shell", minimum: 2

      # A move inside one column never touches `label`, so this only arrives if
      # the reorder itself broadcasts.
      order = []
      reversed = false
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 15

      while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        order = inbox_order
        moved = order.index(card_id(@message3))
        anchor = order.index(card_id(@message1))
        break if (reversed = !moved.nil? && !anchor.nil? && moved > anchor)

        sleep 0.2
      end

      assert reversed,
             "expected #{card_id(@message3)} after #{card_id(@message1)}, saw #{order.inspect}"
    end

    assert_operator @message3.reload.position, :>, @message1.reload.position
  end

  test 'a follower watches a card being carried, and nothing outlives the drop' do
    open_board_as(:ana, @bob)
    open_board_as(:tom, @charlie)

    using_session(:tom) { assert_selector '[data-presence-here]', wait: 10 }
    using_session(:ana) { click_button 'Share my cursor' }
    using_session(:tom) { find(".viewer[data-viewer-id='#{@bob.id}'][data-sharing='true']", wait: 10).click }

    using_session(:ana) do
      # Only once Tom's watch has arrived does Ana sample at all.
      assert_selector ".viewer[data-watching='#{@bob.id}']", wait: 10
      drag_card_to(@message1, 'archive', hold: true)
    end

    using_session(:tom) do
      # A native drag fires dragover, not mousemove. All of this arrives only if
      # the sampler listens to it.
      assert_selector "[data-card-id='#{card_id(@message1)}'][data-presence-busy='#{@bob.name}'][data-lifted='true']", wait: 10
      assert_selector "[data-column='archive'][data-incoming='#{@bob.name}']", wait: 10
      assert_selector ".reactive-presence-cursor[data-presence-user='#{@bob.name}']", visible: :all, wait: 10
      assert_selector '.drag-preview', visible: :all, wait: 10
    end

    using_session(:ana) { drag_card_to(@message1, 'archive') }

    using_session(:tom) do
      # Nobody moves the mouse here, so the markers must clear on their own.
      assert_selector "[data-column='archive'] [data-card-id='#{card_id(@message1)}']", wait: 10
      assert_no_selector '.drag-preview', visible: :all, wait: 10
      assert_no_selector '[data-lifted]', wait: 10
      assert_no_selector '[data-incoming]', wait: 10
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

  # One atomic read. Cards are being relocated and animated while this polls,
  # and a Capybara node fetched a moment ago can be obsolete by the time its
  # attribute is read.
  def inbox_order
    page.evaluate_script(%([...document.querySelectorAll("[data-column='inbox'] .card-shell")].map(s => s.dataset.cardId)))
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

  # Cuprite has no native drag, so drive the same DragEvents the browser would,
  # through the same data-action bindings. `hold: true` leaves the card in the
  # air so the other session can look at it mid-drag.
  def drag_card_to(message, label, hold: false, after: nil)
    page.execute_script(<<~JS, card_id(message), label, after && card_id(after), hold)
      const [cardId, label, afterId, hold] = arguments
      const shell = document.querySelector(`[data-card-id="${cardId}"]`)
      const column = document.querySelector(`[data-column="${label}"]`)
      const dt = new DataTransfer()
      const from = shell.getBoundingClientRect()
      const to = column.getBoundingClientRect()
      let y = to.top + 20
      if (afterId) { const r = document.querySelector(`[data-card-id="${afterId}"]`).getBoundingClientRect(); y = r.top + r.height * 0.8 }

      shell.dispatchEvent(new DragEvent("dragstart", { bubbles: true, cancelable: true, dataTransfer: dt, clientX: from.left + 10, clientY: from.top + 10 }))
      for (let i = 1; i <= 4; i++) {
        column.dispatchEvent(new DragEvent("dragover", { bubbles: true, cancelable: true, dataTransfer: dt,
          clientX: from.left + (to.left + 30 - from.left) * i / 4, clientY: from.top + (y - from.top) * i / 4 }))
      }
      if (hold) return
      column.dispatchEvent(new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer: dt, clientX: to.left + 30, clientY: y }))
      shell.dispatchEvent(new DragEvent("dragend", { bubbles: true, cancelable: true, dataTransfer: dt }))
    JS
  end

  def release_card(message)
    page.execute_script(<<~JS, card_id(message))
      const shell = document.querySelector(`[data-card-id="${arguments[0]}"]`)
      shell.dispatchEvent(new DragEvent("dragend", { bubbles: true, cancelable: true, dataTransfer: new DataTransfer() }))
    JS
  end

  # Drops `message` just below `target`, which is what the pointer being past
  # that card's midpoint means.
  def drop_card_after(message, target, label)
    drag_card_to(message, label, after: target)
  end
end
