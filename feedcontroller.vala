

namespace GmailFeed {

   /**
    * Types of actions that we want the feed to perfom
    **/
   internal enum FeedActionType {
      READ,
      STAR,
      UNSTAR,
      ARCHIVE,
      SPAM,
      TRASH,
      UPDATE,
      LOGIN,
      LOGOUT,
      SET_OAUTH_ID,
      AUTHORIZE,
      SET_AUTH_CODE,
      QUIT
   }

   /**
    * An action has an id for the message to act on and the type of action that should be taken
    **/
   internal class FeedAction : GLib.Object {
      public string id {get; set; default = "";}
      public FeedActionType action {get; set;}
   }

   internal class OAuthIdAction : FeedAction {
      public string clientId     {get; set; default = "";}
      public string clientSecret {get; set; default = "";}
      public string redirectUri  {get; set; default = "";}
   }

   /**
    * FeedController exists because we need a way to separate the GUI thread and the message thread.
    * We use an async queue to get actions to the message thread then use Idle callbacks to
    * get response signals back on the GUI thread.
    **/
   public class FeedController : GLib.Object {
      public signal void newMessage(GMessage msg);
      public signal void updatedMessage(GMessage msg);
      public signal void messageStarred(string id);
      public signal void messageUnstarred(string id);
      public signal void messageRemoved(string id);
      public signal void messageRead(string id);
      public signal void messageArchived(string id);
      public signal void messageTrashed(string id);
      public signal void messageSpammed(string id);
      public signal void loginSuccess();
      public signal void loggedOut();
      public signal void feedClosed();
      public signal void updateComplete();
      public signal void feedError(AuthError error);
      public signal void requestAuthCode(string url);


      /**
       * Our feed object. The queue we use to go between threads, and the thread the feed runs on.
       **/
      private Feed? feed;
      private AsyncQueue<FeedAction> queue;
      private Thread<void*> thread;

      /**
       * Create the feed and the feed thread and start them running
       **/
      public FeedController() {
         this.feed = null;
         this.queue  = new AsyncQueue<FeedAction>();
         this.thread = new Thread<void*>("Feed thread", run);
      }

      protected void createFeed(string address) {
         this.feed = new Feed(address);
         this.feed.loadInfo();
         connectSignals();
         var res = this.feed.update();
         if(res == AuthError.SUCCESS) {
            Idle.add(() => {
               this.loginSuccess();
               return false;
            });
         }
      }

      protected void destroyFeed() {
         //disconnectSignals();
         this.feed = null;
      }

      /**
       * Take items off the queue, perform the specified action, repeat.
       * Responses happen as signals so we don't need to worry about them here.
       **/
      private void *run() {
         while(true) {
            var data = queue.pop();
            var s = data.id;
            switch(data.action) {
               case FeedActionType.READ    : this.wrapError(this.feed.markRead(s)); break;
               case FeedActionType.STAR    : this.wrapError(this.feed.starMsg(s)); break;
               case FeedActionType.UNSTAR  : this.wrapError(this.feed.unstarMsg(s)); break;
               case FeedActionType.ARCHIVE : this.wrapError(this.feed.archive(s)); break;
               case FeedActionType.SPAM    : this.wrapError(this.feed.spam(s)); break;
               case FeedActionType.TRASH   : this.wrapError(this.feed.trash(s)); break;
               case FeedActionType.UPDATE  : this.feed.update(); break;
               case FeedActionType.LOGIN :
                  this.createFeed(s);
                  break;
               case FeedActionType.SET_OAUTH_ID :
                  var id_act = data as OAuthIdAction;
                  var result = this.feed.setOAuthInfo(id_act.clientId,
                                                      id_act.clientSecret,
                                                      id_act.redirectUri);
                  this.wrapError(result);
                  break;
               case FeedActionType.AUTHORIZE :
                  var url = this.feed.getAuthUrl();

                  Idle.add(() => {
                     this.requestAuthCode(url);
                     return false;
                  });
                  break;
               case FeedActionType.SET_AUTH_CODE:
                  var result = this.feed.setAuthCode(s);

                  if(result == AuthError.SUCCESS) {
                     this.feed.update();
                  } else {
                     wrapError(result);
                  }
                  break;
               case FeedActionType.LOGOUT:
                  this.destroyFeed();
                  break;
               case FeedActionType.QUIT :
                  Idle.add(() => {
                     this.feedClosed();
                     return false;
                  });
                  return null;
            }
         }
      }

      /**
       * Queues an action of the given type, with the optional id
       **/
      private void pushAction(FeedActionType type, string id = "") {
         var act = new FeedAction();
         act.id = id;
         act.action = type;
         queue.push(act);
      }


      /**
       * To shutdown we need to get the message thread to stop. We want to let any queued
       * actions complete first though.
       **/
      public void shutdown() {
         this.pushAction(FeedActionType.QUIT);
      }

      /**
       * We need to get signals onto a different thread. We do this by adding Idle callbacks
       * with the same content which will run on the GUI thread.
       **/
      private void connectSignals() {
         this.feed.newMessage.connect((m) => {
            Idle.add(() => {
               this.newMessage(new GMessage.copy(m));
               return false;
            });
         });

         this.feed.updatedMessage.connect((m) => {
            Idle.add(() => {
               this.updatedMessage(new GMessage.copy(m));
               return false;
            });
         });

         this.feed.messageStarred.connect((m) => {
            Idle.add(() => {
               this.messageStarred(m);
               return false;
            });
         });

         this.feed.messageUnstarred.connect((m) => {
            Idle.add(() => {
               this.messageUnstarred(m);
               return false;
            });
         });

         this.feed.messageArchived.connect((m) => {
            Idle.add(() => {
               this.messageArchived(m);
               return false;
            });
         });

         this.feed.messageTrashed.connect((m) => {
            Idle.add(() => {
               this.messageTrashed(m);
               return false;
            });
         });

         this.feed.messageSpammed.connect((m) => {
            Idle.add(() => {
               this.messageSpammed(m);
               return false;
            });
         });

         this.feed.messageRead.connect((m) => {
            Idle.add(() => {
               this.messageRead(m);
               return false;
            });
         });

         this.feed.messageRemoved.connect((m) => {
            Idle.add(() => {
               this.messageRemoved(m);
               return false;
            });
         });

         this.feed.updateComplete.connect((res) => {
            Idle.add(() => {
               if(res == AuthError.SUCCESS) {
                  this.updateComplete();
               } else {
                  this.wrapError(res);
               }
               return false;
            });
         });

      }

      /**
       * These methods take care of getting the correct info into the queue to complete the
       * desired actions.
       **/
      public void update() {
         this.pushAction(FeedActionType.UPDATE);
      }

      public void markRead(string id) {
         this.pushAction(FeedActionType.READ, id);
      }

      public void starMsg(string id) {
         this.pushAction(FeedActionType.STAR, id);
      }

      public void unstarMsg(string id) {
         this.pushAction(FeedActionType.UNSTAR, id);
      }

      public void archive(string id) {
         this.pushAction(FeedActionType.ARCHIVE, id);
      }

      public void trash(string id) {
         this.pushAction(FeedActionType.TRASH, id);
      }

      public void spam(string id) {
         this.pushAction(FeedActionType.SPAM, id);
      }

      public void login(string address) {
         this.pushAction(FeedActionType.LOGIN, address);
      }

      public void setOAuthId(string clientId, string clientSecret, string redirectUri) {
         var action = new OAuthIdAction();
         action.clientId     = clientId;
         action.clientSecret = clientSecret;
         action.redirectUri  = redirectUri;
         action.action       = FeedActionType.SET_OAUTH_ID;
         queue.push(action);
      }

      public void getAuthCode() {
         this.pushAction(FeedActionType.AUTHORIZE, "");
      }

      public void setAuthCode(string code) {
         this.pushAction(FeedActionType.SET_AUTH_CODE, code);
      }

      public void logout() {
         this.pushAction(FeedActionType.LOGOUT, "");
      }

      protected void wrapError(AuthError error) {
         if(error != AuthError.SUCCESS) {
            Idle.add(() => {
               this.feedError(error);
               return false;
            });
         }
      }

   }
}

