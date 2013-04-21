
namespace GmailFeed {

	public struct MessageInfo {
		string author;
		string subject;
		string summary;
	}

	[DBus (name="org.wrowclif.GmailNotify")]
	public interface GmailDbusInterface : Object {

		public abstract void get_message_count(out int count) throws IOError;

		public abstract void get_message_list(out MessageInfo[] messages) throws IOError;

		public abstract void get_account_name(out string name) throws IOError;

		public abstract void open_message_window() throws IOError;
	}

	[DBus (name="org.gnome.Shell.SearchProvider2")]
	public class GmailSearch : Object {

		Gee.Map<int, GmailDbusInterface> clients;

		public GmailSearch() {
			clients = new Gee.TreeMap<int, GmailDbusInterface>();
		}

		/**
		 * Called when a search happens.
		 *
		 * @param terms    The current search terms
		 * @param results  Where to store results we find
		 **/
		public void get_initial_result_set(string[] terms, out string[] results) {
			results = {};
			if(terms.length > 0 && terms[0] == "gmail") {
				var have_messages = false;

				foreach(var client in clients.values) {
					try {
						int count;
						client.get_message_count(out count);

						have_messages |= (count > 0);

						if(have_messages) {
							break;
						}
					} catch(IOError io) {
						stdout.printf("Error getting number of messages for client.\n");
					}
				}

				if(have_messages) {
					results = {"yes"};
				}
			}
		}

		/**
		 * Called when a partial search has already occurred to narrow the results
		 *
		 * @param previous The previous search terms
		 * @param terms    The current search terms
		 * @param results  Where to store results we find
		 **/
		public void get_subsearch_result_set(string[] previous, string[] terms, out string[] results) {
			this.get_initial_result_set(terms, out results);
		}

		/**
		 * Called after we decide we have a result to convert it into something the
		 * shell will display.
		 *
		 * @param results The results we found
		 * @param metas   Where we store the meta values we create
		 **/
		public void get_result_metas(string[] results, out HashTable<string, Variant>[] metas) {
			var message_list = new Gee.ArrayList<HashTable<string, Variant>>();

			foreach(var entry in clients.entries) {
				try {
					MessageInfo[] messages;
					var client_id = "%d".printf(entry.key);
					entry.value.get_message_list(out messages);

					foreach(var message in messages) {
						var meta = new HashTable<string, Variant>(str_hash, str_equal);

						meta["id"] = client_id;
						meta["name"] = "%s : %s".printf(message.author, message.subject);
						meta["description"] = message.summary;
						meta["gicon"] = "fake";

						message_list.add(meta);
					}
				} catch(IOError io) {
					stdout.printf("Error getting message list for client.\n");
				}
			}

			metas = message_list.to_array();

		}

		/**
		 * Activate result happens when the user clicks on the result
		 *
		 * @param identifier The id we set on the meta for this result.
		 * @param terms      The search terms
		 * @param timestamp  When the search happened
		 **/
		public void activate_result(string identifier, string[] terms, uint timestamp) {
			int client_id = int.parse(identifier);

			clients[client_id].open_message_window();
		}

		/**
		 * Launch happens when the user clicks the app icon to the left of the result.
		 *
		 * @param terms     The search terms
		 * @param timestamp When the search happened
		 **/
		public void launch_search(string[] terms, uint timestamp) {

		}

		public void register_client(int client_id, string bus_name) {
			Idle.add(() => {finish_register_client(client_id, bus_name); return false;});
		}

		private void finish_register_client(int client_id, string bus_name) {
			if(clients.has_key(client_id)) {
				return;
			}
			GmailDbusInterface client;
			client = Bus.get_proxy_sync(BusType.SESSION,
										bus_name,
										"/org/wrowclif/GmailNotify");
			clients[client_id] = client;

			uint watch_key = 0;
			watch_key = Bus.watch_name(BusType.SESSION, bus_name, BusNameWatcherFlags.NONE,
								null,
								() => {
									clients.unset(client_id);
									Bus.unwatch_name(watch_key);
								});
		}

	}
}

namespace GmailSearchProvider {
	void main(string[] args) {
		Bus.own_name(BusType.SESSION, "org.wrowclif.GmailSearch", BusNameOwnerFlags.NONE,
					(c) => {c.register_object("/org/wrowclif/GmailSearch", new GmailFeed.GmailSearch());},
					() => {},
					() => stderr.printf ("Could not aquire name\n"));

		new MainLoop().run();
	}
}
