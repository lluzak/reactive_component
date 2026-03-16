import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
import ReactiveRendererController from "reactive_component/controllers/reactive_renderer_controller"

application.register("reactive-renderer", ReactiveRendererController)
eagerLoadControllersFrom("controllers", application)
