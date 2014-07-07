using Gee;
using Gtk;

namespace GmailFeed {

   /**
    * The Mailbox is a collection of MailItems. They are sorted by time received.
    * Actions on the messages are made through the mailbox.
    **/
   public class Mailbox : GLib.Object {
      //{ Members
      /**
       * The list has the messages in sorted order.
       * the map allows for fast access of the desired message.
       **/
      private Gee.List<MessageItem> mail_list;
      private Gee.Map<string, MessageItem> messages;
      //}

      //{ Properties
      /**
       * Mailbox message count
       **/
      public int size {
         get {
            return mail_list.size;
         }
      }

      /**
       * Read only view of the mailbox in sorted order
       **/
      public Gee.List<MessageItem> items {
         owned get {
            return mail_list.read_only_view;
         }
      }
      //}

      public Mailbox() {
         this.mail_list = new ArrayList<MessageItem>();
         this.messages = new HashMap<string, MessageItem>();
      }

      /**
       * Adds a message to the mailbox. Places the message at the proper place in the mail list.
       **/
      public void add_message(MessageItem msg) {
         if(!messages.has_key(msg.id)) {
            messages[msg.id] = msg;
            int i;
            for(i = 0; i < mail_list.size; i++) {
               if(mail_list[i].time.compare(msg.time) < 0) {
                  break;
               }
            }
            mail_list.insert(i, msg);
         }
      }

      /**
       * Gets the mail item with the given id
       **/
      public new MessageItem? get(string id) {
         if(messages.has_key(id)) {
            return messages[id];
         } else {
            return null;
         }
      }

      /**
       * Removes the message with the given id
       **/
      public void remove_message(string id) {
         if(messages.has_key(id)) {
            MessageItem mess = null;
            messages.unset(id, out mess);
            mail_list.remove(mess);
         }
      }

      /**
       * Reactivates all messages in the mailbox.
       * This is called on error to ensure the mailbox is functional again.
       **/
      public void reactivate_all() {
         foreach(var mess in mail_list) {
            mess.resetActions();
         }
      }
   }

   [GtkTemplate (ui = "/org/wrowclif/gmailnotify/ui/message_visual.ui")]
   public class MessageItem : Box {
      //{ Static data
      public enum RemoveAction {
         NONE      = 0,
         MARK_READ = 1,
         ARCHIVE   = 2,
         SPAM      = 3,
         TRASH     = 4
      }

      /**
       * These images are static because they can be reused by all messages.
       **/
      private static Gdk.Pixbuf STAR_FULL;
      private static Gdk.Pixbuf STAR_EMPTY;
      private static Gdk.Pixbuf STAR_HALF;

      static construct {
         // This is the directory the images are located in.
         var base_dir = "/usr/share/gmailnotify";

         try {
            STAR_FULL  = new Gdk.Pixbuf.from_file_at_size(
                                    "%s/star_full.png".printf(base_dir), 16, 16);
            STAR_EMPTY = new Gdk.Pixbuf.from_file_at_size(
                                    "%s/star_empty.png".printf(base_dir), 16, 16);
            STAR_HALF  = new Gdk.Pixbuf.from_file_at_size(
                                    "%s/star_half.png".printf(base_dir), 16, 16);
         } catch(GLib.Error e) {
            stderr.printf("Could not load images\n");
         }
      }

      private static const string inactiveTemplate =
         "<small><span foreground='darkred'>%s</span>%s</small>";

      private static const string hoverTemplate =
         "<small><u><span foreground='darkred'>%s</span></u>%s</small>";

      private static const string activeTemplate =
         "<small><i><u><span foreground='darkred'>%s</span></u></i>%s</small>";
      //}

      //{ Template members
      [GtkChild]
      private Label subjectLbl;

      [GtkChild]
      private Label fromLbl;

      [GtkChild]
      private Label summaryLbl;

      [GtkChild]
      private Image starImg;

      [GtkChild]
      private Label markReadLbl;

      [GtkChild]
      private Label archiveLbl;

      [GtkChild]
      private Label spamLbl;

      [GtkChild]
      private Label trashLbl;
      //}

      //{ Members

      /**
       * The controller that interacts with Gmail for us.
       **/
      private FeedController feed;

      /**
       * The action we are currently performing, or RemoveAction.NONE if we haven't
       * started an action yet.
       **/
      private RemoveAction curAction;

      /**
       * Whether the user should be able to change the star state of the message currently.
       **/
      private bool starEnabled;

      /**
       * Whether the message is starred or not. We update this variable to
       * match the state of our internal `msg` when `updateMessage()` is called.
       * Otherwise it tracks the current state of the star. We do not want to modify `msg`
       * ourselves, which is why we have this variable.
       **/
      private bool starred;
      //}

      //{ Properties

      /**
       * This message's id.
       **/
      public string id {
         get {
            return this.msg.id;
         }
      }

      /**
       * When this message was sent.
       **/
      public DateTime time {
         get {
            return this.msg.time;
         }
      }

      /**
       * All the details we know about the message.
       **/
      public GMessage msg {get; private set;}
      //}

      public MessageItem(GMessage msg, FeedController feed) {
         this.curAction = RemoveAction.NONE;
         this.starEnabled = true;

         this.feed = feed;
         this.updateMessage(msg);

         this.feed.messageStarred.connect(this.onMessageStarred);
         this.feed.messageUnstarred.connect(this.onMessageUnstarred);
      }

      /**
       * Update the view to match the state of the message.
       *
       * @param msg: The message we are showing.
       **/
      public void updateMessage(GMessage msg) {
         this.msg = msg;

         this.starred = this.msg.starred;
         this.starImg.pixbuf = this.starred ? STAR_FULL : STAR_EMPTY;

         this.subjectLbl.label = this.msg.subject;
         this.fromLbl.label    = this.msg.author;

         this.summaryLbl.set_markup(this.msg.summary);

         //{ Set the styling for the removal actions
         this.onMarkReadLeave();
         this.onArchiveLeave();
         this.onSpamLeave();
         this.onTrashLeave();
         //}
      }

      /**
       * Called when the feed successfully stars a message.
       *
       * Note: This signal is sent in response to a request made by us.
       *       If the star state is changed through the gmail website or
       *       other means, we will get that update via an `updateMessage()` call.
       *
       * @param id: The id of the message that was starred.
       **/
      private void onMessageStarred(string id) {
         // We get this signal when any message is starred, so we
         // need to check if if applies to this message before doing anything.
         if(id == this.msg.id) {
            this.starred     = true;
            this.starEnabled = true;
            this.starImg.pixbuf = STAR_FULL;
         }
      }

      /**
       * Called when the feed successfully unstars a message.
       *
       * Note: This signal is sent in response to a request made by us.
       *       If the star state is changed through the gmail website or
       *       other means, we will get that update via an `updateMessage()` call.
       *
       * @param id: The id of the message that was starred.
       **/
      private void onMessageUnstarred(string id) {
         // We get this signal when any message is unstarred, so we
         // need to check if if applies to this message before doing anything.
         if(id == this.msg.id) {
            this.starred     = false;
            this.starEnabled = true;
            this.starImg.pixbuf = STAR_EMPTY;
         }
      }


      //{ Star
      [GtkCallback]
      private bool onStarEnter() {
         if(this.starEnabled) {
            this.starImg.pixbuf = STAR_HALF;
         }
         return false;
      }

      [GtkCallback]
      private bool onStarLeave() {
         if(this.starEnabled) {
            this.starImg.pixbuf = this.starred ? STAR_FULL : STAR_EMPTY;
         }
         return false;
      }

      [GtkCallback]
      private bool onStarClicked() {
         if(this.starEnabled) {
            this.starEnabled = false;

            // The feed distinguishes between starring and unstarring, but we
            // use a single button for both. So we check our state to determine
            // which call to make.
            if(this.starred) {
               feed.unstarMsg(this.msg.id);
            } else {
               feed.starMsg(this.msg.id);
            }
         }
         return false;
      }
      //}

      //{ Mark read
      [GtkCallback]
      private bool onMarkReadEnter() {
         if(this.curAction == RemoveAction.NONE) {
            this.markReadLbl.set_markup(hoverTemplate.printf("Mark as read", " |"));
         }
         return false;
      }

      [GtkCallback]
      private bool onMarkReadLeave() {
         if(this.curAction == RemoveAction.NONE) {
            this.markReadLbl.set_markup(inactiveTemplate.printf("Mark as read", " |"));
         }
         return false;
      }

      [GtkCallback]
      private bool onMarkReadClicked() {
         if(this.curAction == RemoveAction.NONE) {
            this.markReadLbl.set_markup(activeTemplate.printf("Marking as read...", " |"));
            this.curAction = RemoveAction.MARK_READ;
            feed.markRead(this.msg.id);
         }
         return false;
      }
      //}

      //{ Archive
      [GtkCallback]
      private bool onArchiveEnter() {
         if(this.curAction == RemoveAction.NONE) {
            this.archiveLbl.set_markup(hoverTemplate.printf("Archive", " |"));
         }
         return false;
      }

      [GtkCallback]
      private bool onArchiveLeave() {
         if(this.curAction == RemoveAction.NONE) {
            this.archiveLbl.set_markup(inactiveTemplate.printf("Archive", " |"));
         }
         return false;
      }

      [GtkCallback]
      private bool onArchiveClicked() {
         if(this.curAction == RemoveAction.NONE) {
            this.archiveLbl.set_markup(activeTemplate.printf("Archiving...", " |"));
            this.curAction = RemoveAction.ARCHIVE;
            feed.archive(this.msg.id);
         }
         return false;
      }
      //}

      //{ Spam
      [GtkCallback]
      private bool onSpamEnter() {
         if(this.curAction == RemoveAction.NONE) {
            this.spamLbl.set_markup(hoverTemplate.printf("Report spam", " |"));
         }
         return false;
      }

      [GtkCallback]
      private bool onSpamLeave() {
         if(this.curAction == RemoveAction.NONE) {
            this.spamLbl.set_markup(inactiveTemplate.printf("Report spam", " |"));
         }
         return false;
      }

      [GtkCallback]
      private bool onSpamClicked() {
         if(this.curAction == RemoveAction.NONE) {
            this.spamLbl.set_markup(activeTemplate.printf("Reporting spam...", " |"));
            this.curAction = RemoveAction.SPAM;
            feed.spam(this.msg.id);
         }
         return false;
      }
      //}

      //{ Trash
      [GtkCallback]
      private bool onTrashEnter() {
         if(this.curAction == RemoveAction.NONE) {
            this.trashLbl.set_markup(hoverTemplate.printf("Delete", ""));
         }
         return false;
      }

      [GtkCallback]
      private bool onTrashLeave() {
         if(this.curAction == RemoveAction.NONE) {
            this.trashLbl.set_markup(inactiveTemplate.printf("Delete", ""));
         }
         return false;
      }

      [GtkCallback]
      private bool onTrashClicked() {
         if(this.curAction == RemoveAction.NONE) {
            this.trashLbl.set_markup(activeTemplate.printf("Deleting...", ""));
            this.curAction = RemoveAction.TRASH;
            feed.trash(this.msg.id);
         }
         return false;
      }
      //}

      /**
       * Called when we recover from a connection error of some sort.
       * Resets the view so that it will respond to user interactions again.
       *
       * When we begin an action we freeze the message UI until that action completes.
       * If the connection fails while we are trying to make the request, we need to get
       * back into a state where we can retry.
       **/
      public void resetActions() {
         this.curAction   = RemoveAction.NONE;
         this.starEnabled = true;
      }

   }

}
