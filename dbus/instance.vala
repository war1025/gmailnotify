
namespace GmailFeed {

   public delegate int MessageCountDelegate();
   public delegate Gee.List<MessageItem> MessageListDelegate();
   public delegate string AccountNameDelegate();
   public delegate void ShowMessagesDelegate();

   public delegate void FeedChangeDelegate();
   public delegate void ConnectedChangeDelegate(bool connected);
   public delegate void ConnectSignalsDelegate(FeedChangeDelegate changeDelegate,
                                               ConnectedChangeDelegate connectedDelegate);


   [DBus (name="org.wrowclif.GmailNotify.Instance")]
   public class DbusInstance : Object {

      private unowned MessageCountDelegate count_delegate;
      private unowned MessageListDelegate  list_delegate;
      private unowned AccountNameDelegate  name_delegate;
      private unowned ShowMessagesDelegate show_messages_delegate;

      public signal void messages_changed();
      public signal void connected_changed(bool connected);

      public DbusInstance(MessageCountDelegate   count_delegate,
                          MessageListDelegate    list_delegate,
                          AccountNameDelegate    name_delegate,
                          ShowMessagesDelegate   show_messages_delegate,
                          ConnectSignalsDelegate connect_delegate) {
         this.count_delegate         = count_delegate;
         this.list_delegate          = list_delegate;
         this.name_delegate          = name_delegate;
         this.show_messages_delegate = show_messages_delegate;

         connect_delegate(emit_messages_changed, emit_connected_changed);
      }

      private void emit_messages_changed() {
         messages_changed();
      }

      private void emit_connected_changed(bool connected) {
         connected_changed(connected);
      }

      public void get_message_count(out int count) {
         count = count_delegate();
      }

      public void get_message_list(out MessageInfo[] messages) {
         var mail_items = list_delegate();

         messages = new MessageInfo[mail_items.size];

         for(int i = 0; i < mail_items.size; i++) {
            var mail_item = mail_items[i];

            messages[i] = { mail_item.msg.author,
                            mail_item.msg.subject,
                            mail_item.msg.summary};
         }

      }

      public void get_account_name(out string name) {
         name = name_delegate();
      }

      public void open_message_window() {
         show_messages_delegate();
      }
   }

   void register_instance(DbusInstance instance) {
      var cur_pid = Posix.getpid();

      var bus_name = "org.wrowclif.GmailNotify.Instance%d".printf(cur_pid);

      Bus.own_name(BusType.SESSION, bus_name, BusNameOwnerFlags.NONE,
               (c) => {c.register_object(DbusInstanceInterface.OBJECT_PATH, instance);},
               () => {},
               () => stderr.printf ("Could not aquire name\n"));

      Bus.watch_name(BusType.SESSION, DbusHubInterface.BUS_NAME, BusNameWatcherFlags.NONE,
                     (connection, name, owner) => {
                        DbusHubInterface gsi;
                        gsi = Bus.get_proxy_sync(BusType.SESSION,
                                                 DbusHubInterface.BUS_NAME,
                                                 DbusHubInterface.OBJECT_PATH);

                        gsi.register_instance({cur_pid, bus_name});
                     });

      DbusHubInterface hub;
      hub = Bus.get_proxy_sync(BusType.SESSION,
                               DbusHubInterface.BUS_NAME,
                               DbusHubInterface.OBJECT_PATH);
   }
}
