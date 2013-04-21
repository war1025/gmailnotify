
namespace GmailFeed {

	public delegate int MessageCountDelegate();
	public delegate Gee.List<MailItem> MessageListDelegate();
	public delegate string AccountNameDelegate();
	public delegate void ShowMessagesDelegate();

	[DBus (name="org.wrowclif.GmailNotify")]
	public class GmailDbus: GLib.Object {

		private unowned MessageCountDelegate count_delegate;
		private unowned MessageListDelegate  list_delegate;
		private unowned AccountNameDelegate  name_delegate;
		private unowned ShowMessagesDelegate show_messages_delegate;

		public GmailDbus(MessageCountDelegate count_delegate,
		                 MessageListDelegate list_delegate,
						 AccountNameDelegate name_delegate,
						 ShowMessagesDelegate show_messages_delegate) {
			this.count_delegate         = count_delegate;
			this.list_delegate          = list_delegate;
			this.name_delegate          = name_delegate;
			this.show_messages_delegate = show_messages_delegate;
		}

		public void get_message_count(out int count) {
			count = count_delegate();
		}

		public void get_message_list(out MessageInfo[] messages) {
			var mail_items = list_delegate();

			messages = new MessageInfo[mail_items.size];

			for(int i = 0; i < mail_items.size; i++) {
				var mail_item = mail_items[i];
				messages[i] = { mail_item.author,
				                mail_item.subject,
								mail_item.summary};
			}

		}

		public void get_account_name(out string name) {
			name = name_delegate();
		}

		public void open_message_window() {
			show_messages_delegate();
		}
	}

	[DBus (name="org.gnome.Shell.SearchProvider2")]
	public interface GmailSearchInterface : Object {

		public abstract void register_client(int client_id, string bus_name) throws IOError;
	}

	void register_instance(GmailDbus instance) {
		var cur_pid = Posix.getpid();

		var bus_name = "org.wrowclif.GmailNotify%d".printf(cur_pid);

		Bus.own_name(BusType.SESSION, bus_name, BusNameOwnerFlags.NONE,
					(c) => {c.register_object("/org/wrowclif/GmailNotify", instance);},
					() => {},
					() => stderr.printf ("Could not aquire name\n"));

		Bus.watch_name(BusType.SESSION, "org.wrowclif.GmailSearch", BusNameWatcherFlags.NONE,
					(connection, name, owner) => {
						GmailSearchInterface gsi;
						gsi = Bus.get_proxy_sync(BusType.SESSION,
												 "org.wrowclif.GmailSearch",
												 "/org/wrowclif/GmailSearch");

						gsi.register_client(cur_pid, bus_name);
					});
	}

	public struct MessageInfo {
		string author;
		string subject;
		string summary;
	}
}
