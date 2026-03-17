# Pin npm packages by running ./bin/importmap

pin "application", to: "/application.js"
pin "@hotwired/turbo-rails", to: "/vendor/turbo.min.js"
pin "@hotwired/stimulus", to: "/vendor/stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "/vendor/stimulus-loading.js"
pin "@rails/actioncable", to: "/vendor/actioncable.esm.js"
pin "controllers", to: "/controllers/index.js"
pin "controllers/application", to: "/controllers/application.js"
pin "reactive_component/controllers/reactive_renderer_controller", to: "/reactive_component/controllers/reactive_renderer_controller.js"
pin "reactive_component/lib/reactive_renderer_utils", to: "/reactive_component/lib/reactive_renderer_utils.js"
