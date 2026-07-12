module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      return unless (session_id = cookies.signed[:session_id])
      return unless (session = Session.find_by(id: session_id))

      if session.expired?
        session.destroy
        cookies.delete(:session_id)
        nil
      else
        # 利用があれば有効期限を延長する(DB 書き込みと Set-Cookie は間引き間隔ごと)。
        set_session_cookie(session) if session.refresh_activity
        session
      end
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_new_session_for(admin)
      # ログインを契機に、放置された期限切れセッションを掃除する(Session にコールバックは無い)。
      Session.expired.delete_all

      admin.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        set_session_cookie(session)
      end
    end

    def set_session_cookie(session)
      cookies.signed[:session_id] = {
        value: session.id, httponly: true, same_site: :lax, expires: Session::LIFETIME.from_now
      }
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
