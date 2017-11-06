require_dependency 'webpush'

module DiscoursePushNotifications
  class Pusher
    def self.push(user, payload)
      updated = false

      subscriptions(user).each do |_, subscription|
        subscription = JSON.parse(subscription)

        message = {
          title: I18n.t(
            "discourse_push_notifications.popup.#{Notification.types[payload[:notification_type]]}",
            site_title: SiteSetting.title,
            topic: payload[:topic_title],
            username: payload[:username]
          ),
          body: payload[:excerpt],
          icon: SiteSetting.logo_small_url || SiteSetting.logo_url,
          tag: "#{Discourse.current_hostname}-#{payload[:topic_id]}",
          base_url: "#{Discourse.base_url}",
          url: "#{payload[:post_url]}"
        }

        begin
          response = Webpush.payload_send(
            endpoint: subscription["endpoint"],
            message: message.to_json,
            p256dh: subscription.dig("keys", "p256dh"),
            auth: subscription.dig("keys", "auth"),
            vapid: {
              subject: Discourse.base_url,
              public_key: SiteSetting.vapid_public_key,
              private_key: SiteSetting.vapid_private_key
            }
          )
        rescue Webpush::InvalidSubscription => e
          # Delete the subscription from Redis
          updated = true
          subscriptions(user).delete(extract_unique_id(subscription))
        end
      end

      user.save_custom_fields(true) if updated
    end

    SUBSCRIPTION_KEY = "subscriptions".freeze

    def self.subscriptions(user)
      user.custom_fields[DiscoursePushNotifications::PLUGIN_NAME] ||= {}
      user.custom_fields[DiscoursePushNotifications::PLUGIN_NAME][SUBSCRIPTION_KEY] ||= {}
      user.custom_fields[DiscoursePushNotifications::PLUGIN_NAME][SUBSCRIPTION_KEY]
    end

    def self.clear_subscriptions(user)
      user.custom_fields[DiscoursePushNotifications::PLUGIN_NAME] = {}
    end

    def self.subscribe(user, subscription, send_confirmation)
      subscriptions(user)[extract_unique_id(subscription)] = subscription.to_json
      user.save_custom_fields(true)
      if send_confirmation == "true"
        message = {
          title: I18n.t("discourse_push_notifications.popup.confirm_title",
                        site_title: SiteSetting.title),
          body: I18n.t("discourse_push_notifications.popup.confirm_body"),
          icon: SiteSetting.logo_small_url || SiteSetting.logo_url,
          tag: "#{Discourse.current_hostname}-subscription"
        }

        begin
          response = Webpush.payload_send(
            endpoint: subscription["endpoint"],
            message: message.to_json,
            p256dh: subscription.dig("keys", "p256dh"),
            auth: subscription.dig("keys", "auth"),
            vapid: {
              subject: Discourse.base_url,
              public_key: SiteSetting.vapid_public_key,
              private_key: SiteSetting.vapid_private_key
            }
          )
        rescue Webpush::InvalidSubscription => e
        end
      end
    end

    def self.unsubscribe(user, subscription)
      subscriptions(user).delete(extract_unique_id(subscription))
      user.save_custom_fields(true)
    end

    protected

    def self.extract_unique_id(subscription)
      subscription["endpoint"].split("/").last
    end
  end
end
