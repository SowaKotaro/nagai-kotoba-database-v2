class Current < ActiveSupport::CurrentAttributes
  attribute :session
  delegate :admin, to: :session, allow_nil: true
end
