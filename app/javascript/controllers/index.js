// Import and register all your controllers from the importmap via controllers/**/*_controller
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"

eagerLoadControllersFrom("controllers", application)


// import { application } from "./application"

// import NestedAddressesController from "./nested_addresses_controller"
// application.register("nested-addresses", NestedAddressesController)
