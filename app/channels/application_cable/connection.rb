module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_admin

    def connect
      set_current_admin || reject_unauthorized_connection
    end

    private
      def set_current_admin
        if session = Session.find_by(id: cookies.signed[:session_id])
          self.current_admin = session.admin
        end
      end
  end
end
