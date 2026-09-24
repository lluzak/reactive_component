import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
import ReactiveRendererController from "reactive_component/controllers/reactive_renderer_controller"
import PresenceController from "reactive_component/controllers/presence_controller"
import BoardController from "controllers/board_controller"

application.register("reactive-renderer", ReactiveRendererController)
application.register("presence", PresenceController)
application.register("board", BoardController)
eagerLoadControllersFrom("controllers", application)
