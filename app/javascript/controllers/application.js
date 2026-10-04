import { Application } from "@hotwired/stimulus"

const application = Application.start()

// Configure Stimulus development experience
application.debug = false
// システムテストの wait_for_stimulus(test/application_system_test_case.rb)が、コントローラの
// 接続を待つのに window.Stimulus を使う。消さない
window.Stimulus   = application

export { application }
