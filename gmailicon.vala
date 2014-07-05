using Gtk;

namespace GmailFeed {

   /**
    * The GmailIcon represents the status icon that actually sits in the notification area along
    * with the popup that displays messages when they are received.
    **/
   public class GmailIcon : GLib.Object {

      /**
       * The icon that sits in the notification area
       **/
      private StatusIcon icon;
      /**
       * The right click menu
       **/
      private Gtk.Menu popup_menu;
      /**
       * The mailbox where we store the mail we get
       **/
      private Mailbox mailbox;
      /**
       * The feed we are connected to so we can get mail
       **/
      private FeedController feed;
      /**
       * Dbus interface for interacting with this feed
       **/
      private DbusInstance gmail_dbus;

      /**
       * The window and box we will display when the user wants to view their mail.
       * The window is needed for showing and hiding, while the message_box is needed
       * so we can access its contents and update them as needed.
       **/
      private Window message_window;
      private Box message_box;
      /**
       * Position of the top left corner of the window
       **/
      private int window_x;
      private int window_y;
      /**
       * If an update is requested, the message window will be redrawn.
       * Normally the window is only drawn when an update_complete signal is received.
       **/
      private bool request_update;

      /**
       * The dialog box for logging in. Also the delegate for passing our credentials to the feed
       **/
      private LoginDialog loginDialog;

      private AuthorizationDialog authDialog;

      private OAuthDialog oauthDialog;

      /**
       * Update is called automatically every X seconds once logged in. We need to cancel this
       * action if we lose our connection for some reason. So we need to keep track of its id.
       **/
      private uint timer_id;
      private bool timer_set;

      /**
       * The pictures to show in the icon
       **/
      private static string MAIL_ICON = "/usr/share/gmailnotify/mail.png";
      private static string NO_MAIL_ICON = "/usr/share/gmailnotify/nomail.png";
      private static string ERROR_ICON = "/usr/share/gmailnotify/error.png";

      public GmailIcon() {
         icon = new StatusIcon();
         mailbox = new Mailbox();
         feed = new FeedController();
         popup_menu = new Gtk.Menu();
         message_window = new Window(WindowType.POPUP);
         gmail_dbus = new DbusInstance(() => {return mailbox.size;},
                                       () => {return mailbox.items;},
                                       () => {return loginDialog.address;},
                                       show_message_window,
                                       (messages_changed, connected_changed) => {
                                          feed.newMessage.connect(() => {
                                             messages_changed();
                                          });
                                          feed.messageRemoved.connect(() => {
                                             messages_changed();
                                          });

                                          feed.updateComplete.connect(() => {
                                             connected_changed(true);
                                          });

                                          feed.feedError.connect(() => {
                                             connected_changed(false);
                                          });
                                       }
                                      );

         register_instance(gmail_dbus);

         timer_set = false;

         build_icon();
         buildLoginDialog();
         build_message_window();

         connect_feed_mailbox_signals();
         connect_feed_icon_signals();

         icon.set_visible(true);
      }

      /**
       * Constructs the login dialog. This is just a dialog where the user enters their
       * name and password. Since we keep the box around, we have their information saved
       * and can show it later so if reauthentication is needed they just need to
       * click login and not fill out their info again.
       **/
      private void buildLoginDialog() {
         loginDialog = new LoginDialog();
         authDialog  = new AuthorizationDialog();
         oauthDialog = new OAuthDialog();
      }

      /**
       * Calls the login dialog, if the login button is pressed, try to log in.
       **/
      public void login() {
         var response = this.loginDialog.run();

         if(response == LoginDialog.Response.LOGIN) {
            feed.login(this.loginDialog.address);
            icon.set_tooltip_text("Logging In...");
         }

         loginDialog.hide();
      }

      public void authorize() {
         feed.getAuthCode();
         authDialog.authCode = "";

         var response = authDialog.run();

         if(response == AuthorizationDialog.Response.AUTHORIZE) {
            feed.setAuthCode(this.authDialog.authCode);
            icon.set_tooltip_text("Authorizing...");
         }

         authDialog.hide();
      }

      public void setupOAuthId() {
         oauthDialog.clientId     = "";
         oauthDialog.clientSecret = "";
         oauthDialog.redirectUri  = "";

         var response = oauthDialog.run();

         if(response == OAuthDialog.Response.SAVE) {
            feed.setOAuthId(oauthDialog.clientId,
                            oauthDialog.clientSecret,
                            oauthDialog.redirectUri);
            icon.set_tooltip_text("Setting credentials...");
         }

         oauthDialog.hide();
      }



      /**
       * Builds the status icon. This involves building the icon and the popup menu.
       * We also connect the appropriate signals to make it functional.
       **/
      private void build_icon() {
         icon.set_from_file(NO_MAIL_ICON);
         icon.set_tooltip_text("Disconnected...");

         var login = new Gtk.MenuItem.with_label("Login");
         var update = new Gtk.MenuItem.with_label("Update");
         var quit = new Gtk.MenuItem.with_label("Quit");

         login.activate.connect(() => {
            login.hide();
            this.login();
         });

         update.activate.connect(() => {
            feed.update();
            icon.set_tooltip_text("Updating...");
         });

         /**
          * We send the feed a shutdown signal. It sends us a signal back when it is shutdown.
          * Then we receive that signal and stop ourselves.
          **/
         quit.activate.connect(() => {
            feed.shutdown();
         });

         /**
          * This is the shutdown signal that we receive from the feed
          **/
         feed.feedClosed.connect(() => {
            Gtk.main_quit();
         });

         popup_menu.append(login);
         popup_menu.append(update);
         popup_menu.append(quit);

         popup_menu.show_all();
         update.hide();

         feed.updateComplete.connect(() => {
            login.hide();
            update.show();
         });

         feed.feedError.connect(() => {
            login.show();
            update.hide();
         });

         icon.popup_menu.connect((b,t) => {
            popup_menu.popup(null, null, icon.position_menu, b, t);
         });

         /**
          * When the icon is clicked, we want to show the messages if there are any,
          * otherwise we don't want to show an empty window. We resize the window to
          * too small before we show it so that it sizes itself properly and doesn't
          * have extra white space.
          **/
         icon.activate.connect(show_message_window);

      }

      private void show_message_window() {
         if(mailbox.size > 0) {
            if(message_window.visible) {
               message_window.hide();
            } else {
               int x = icon.screen.get_width();

               window_y = 30;
               window_x = x - 405;

               message_window.move(window_x, window_y);
               message_window.resize(5, 5);
               message_window.show_all();
            }
         }
      }


      /**
       * Sets up some basic things for the window that will show the messages.
       **/
      private void build_message_window() {
         Gdk.RGBA white = Gdk.RGBA();
         white.parse("#fff");

         var ebox    = new EventBox();
         message_box = new Box(Orientation.VERTICAL, 5);
         ebox.override_background_color(StateFlags.NORMAL, white);

         /**
          * We want the window to hide if we mouse out of it, but we don't want it to happen immediately in case
          * the user accidentally goes out of the window.
          * So we use a timeout which starts when the user leaves the window, but is cancelled if they re-enter it.
          **/
         uint event_id = 0;
         bool id_set   = false;

         ebox.enter_notify_event.connect((e) => {
            if(id_set) {
               Source.remove(event_id);
               id_set = false;
            }
            return false;
         });

         ebox.leave_notify_event.connect((e) => {
            if(!(e.detail == Gdk.NotifyType.INFERIOR)) {
               event_id = Timeout.add_seconds(1, () => {
                  message_window.hide();
                  return false;
               });
               id_set = true;
            }
            return false;
         });

         ebox.add(message_box);
         message_window.add(ebox);

      }

      /**
       * Set up connections between the mailbox and the feed
       **/
      private void connect_feed_mailbox_signals() {
         // When we get a new message we need to connect its signals to the
         // feed so they will do something useful
         feed.newMessage.connect((m) => {
            var msg = new MessageItem(m, feed);
            mailbox.add_message(msg);
         });

         /**
          * When we get a new message we also need to update the message_box.
          * Since the previous signal connection added the message to the mailbox, and
          * the mailbox is sorted, we look through the mailbox and find where this item should be.
          * Then reposition the visual in the message_box so it is displayed in the
          * correct position.
          **/
         feed.newMessage.connect((m) => {
            var msg = mailbox[m.id];
            int c = 0;
            foreach(var mess in mailbox.items) {
               if(mess.id == msg.id) {
                  message_box.pack_start(msg, false, false, 5);
                  message_box.reorder_child(msg, c);
                  break;
               }
               c++;
            }
         });

         /**
          * Display a notification when new mail is received
          **/
         feed.newMessage.connect((m) => {
            try {
               var notification = new Notify.Notification(m.author, m.subject, MAIL_ICON);
               notification.set_hint("transient", true);
               notification.show();
            } catch(Error e) {
               print("Error sending notification for new message: %s\n", e.message);
            }
         });

         feed.updatedMessage.connect((m) => {
            var mess = mailbox[m.id];

            if(mess != null) {
               mess.updateMessage(m);
            }
         });

         /**
          * The following signals are always followed by a message_removed signal.
          * In that signal we will check if an update of the window is needed. During a normal
          * update several messages might be removed, so we don't want to redraw the window
          * until they are all done, but for an individual message we would like to
          * redraw the window as soon as we have confirmation that it was removed.
          **/
         feed.messageRead.connect(() => {
            request_update = true;
         });

         feed.messageArchived.connect(() => {
            request_update = true;
         });

         feed.messageSpammed.connect(() => {
            request_update = true;
         });

         feed.messageTrashed.connect(() => {
            request_update = true;
         });

         /**
          * We need to remove the message from our message window, since it was removed from
          * the feed. This needs to happen before we remove the message from our mailbox since
          * that is our link to the visual.
          **/
         feed.messageRemoved.connect((id) => {
            var msg = mailbox[id];
            if(msg != null) {
               message_box.remove(msg);
               if(mailbox.size == 1) {
                  message_window.hide();
                  message_window.resize(5, 2);
               }
            }
         });

         /**
          * The message is removed from the feed, so remove it from the mailbox.
          **/
         feed.messageRemoved.connect((id) => {
            mailbox.remove_message(id);
         });

         /**
          * Here we update everything if we have been requested to
          **/
         feed.messageRemoved.connect(() => {
            if(request_update) {
               updateUI();
            }
            request_update = false;
         });

         /**
          * If a connection error occurs we need to reactivate any messages that had pending
          * requests since we don't know if the action went through or not. Otherwise we could
          * have messages stuck in the mailbox that we have no way of removing without a restart
          **/
         feed.feedError.connect(() => {
            mailbox.reactivate_all();
         });
      }

      /**
       * Connect signals from the feed that we want to alter the icon or tooltip in some way.
       **/
      private void connect_feed_icon_signals() {
         feed.loginSuccess.connect(() => {
            icon.set_from_file(NO_MAIL_ICON);
            icon.set_tooltip_text("Updating...");
            feed.update();
            if(timer_set) {
               Source.remove(timer_id);
            }
            timer_id = Timeout.add_seconds(120, () => {
               feed.update();
               return true;
            });
            timer_set = true;
         });

         /**
          * If there is a connection error, show the login box and remove the update timer.
          * If the user cancels the login request, they can select login from the right
          * click menu later.
          **/
         feed.feedError.connect((error) => {
            icon.set_from_file(ERROR_ICON);
            icon.set_tooltip_text("Connection Error...");
            if(error != AuthError.UNKNOWN && timer_set) {
               Source.remove(timer_id);
               timer_set = false;
            } else if(error == AuthError.UNKNOWN) {
               if(!timer_set) {
                  login();
               }
            }

            if(error == AuthError.NEED_TOKEN) {
               login();
            } else if(error == AuthError.INVALID_AUTH) {
               authorize();
            } else if(error == AuthError.NEED_OAUTH_ID) {
               setupOAuthId();
            }
         });

         feed.updateComplete.connect(() => {
            updateUI();
         });

         feed.requestAuthCode.connect((requestUrl) => {
            this.authDialog.url = requestUrl;
         });
      }

      private void updateUI() {
         var count = mailbox.size;
         var user = this.loginDialog.address;
         if(count == 0) {
            icon.set_tooltip_text("%s: No mail...".printf(user));
            icon.set_from_file(NO_MAIL_ICON);
         } else if(count == 1) {
            icon.set_tooltip_text("%s: There is 1 new message...".printf(user));
            icon.set_from_file(MAIL_ICON);
         } else {
            icon.set_tooltip_text("%s: There are %d new messages...".printf(user, count));
            icon.set_from_file(MAIL_ICON);
         }
         if(message_window.visible) {
            message_window.hide();
            message_window.resize(5, 5);
            if(count > 0) {
               message_window.show_all();
            }
         } else {
            message_window.resize(5, 5);
         }
      }
   }

   [GtkTemplate (ui = "/org/wrowclif/gmailnotify/ui/login_dialog.ui")]
   public class LoginDialog : Dialog {
      public enum Response {
         LOGIN = 1,
         CANCEL = 0
      }

      public string address {
         get { return addressEntry.text; }
         set { addressEntry.text = value; }
      }

      [GtkChild]
      private Entry addressEntry;

      public LoginDialog() {


      }

      [GtkCallback]
      private void onLogin() {
         this.response(Response.LOGIN);
      }

      [GtkCallback]
      private void onCancel() {
         this.response(Response.CANCEL);
      }

   }


   [GtkTemplate (ui = "/org/wrowclif/gmailnotify/ui/auth_code_dialog.ui")]
   public class AuthorizationDialog : Dialog {
      public enum Response {
         AUTHORIZE = 1,
         CANCEL    = 0
      }

      public string url {
         get { return authUrlEntry.text; }
         set { authUrlEntry.text = value; }
      }

      public string authCode {
         get { return authCodeEntry.text; }
         set { authCodeEntry.text = value; }
      }

      [GtkChild]
      private Entry authUrlEntry;

      [GtkChild]
      private Entry authCodeEntry;

      public AuthorizationDialog() {


      }

      [GtkCallback]
      private void onAuthorize() {
         this.response(Response.AUTHORIZE);
      }

      [GtkCallback]
      private void onCancel() {
         this.response(Response.CANCEL);
      }

   }


   [GtkTemplate (ui = "/org/wrowclif/gmailnotify/ui/oauth_dialog.ui")]
   public class OAuthDialog : Dialog {
      public enum Response {
         SAVE   = 1,
         CANCEL = 0
      }

      public string clientId {
         get { return clientIdEntry.text; }
         set { clientIdEntry.text = value; }
      }

      public string clientSecret {
         get { return clientSecretEntry.text; }
         set { clientSecretEntry.text = value; }
      }

      public string redirectUri {
         get { return redirectUriEntry.text; }
         set { redirectUriEntry.text = value; }
      }

      [GtkChild]
      private Entry clientIdEntry;

      [GtkChild]
      private Entry clientSecretEntry;

      [GtkChild]
      private Entry redirectUriEntry;

      public OAuthDialog() {


      }

      [GtkCallback]
      private void onSave() {
         this.response(Response.SAVE);
      }

      [GtkCallback]
      private void onCancel() {
         this.response(Response.CANCEL);
      }

   }

   void main(string[] args) {
      Gtk.init(ref args);
      Notify.init("gmail-notify");

      var icon = new GmailIcon();
      icon.login();

      Gtk.main();
   }
}
