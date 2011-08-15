using Gtk;

namespace GmailFeed {

	public class GmailIcon : GLib.Object {
		private StatusIcon icon;
		private Mailbox mailbox;
		private FeedController feed;

		public GmailFeed() {
			icon = new StatusIcon();
			mailbox = new Mailbox();
			feed = new FeedController();

			build_icon();

			connect_feed_mailbox_signals();
		}

		private void build_icon() {

		}

		private void connect_feed_mailbox_signals() {
			feed.new_message.connect((m) => {
				mailbox.add_message(m);
			});

			feed.message_removed.connect((id) => {
				mailbox.remove_message(id);
			});

			feed.message_starred.connect((id) => {
				mailbox.star_message(id);
			});

			feed.message_unstarred.connect((id) => {
				mailbox.unstar_message(id);
			});

			feed.message_important.connect((id) => {
				mailbox.important_message(id);
			});

			feed.message_unimportant.connect((id) => {
				mailbox.unimportant_message(id);
			});
		}
	}
}
