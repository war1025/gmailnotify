
namespace GmailFeed {

   /**
    * An individual GmailNotify instance implements this interface.
    **/
   [DBus (name="org.wrowclif.GmailNotify.Instance")]
   public interface DbusInstanceInterface : Object {

      public static const string OBJECT_PATH = "/org/wrowclif/GmailNotify/Instance";

      public abstract void get_message_count(out int count) throws IOError;

      public abstract void get_message_list(out MessageInfo[] messages) throws IOError;

      public abstract void get_account_name(out string name) throws IOError;

      public abstract void open_message_window() throws IOError;

      public abstract void is_connected(out bool connected) throws IOError;

      public signal void messages_changed();

      public signal void connected_changed(bool connected);
   }

   /**
    * The hub is a central location that all GmailNotifyInstances register with.
    * This allows client programs to follow changes in the current instances in one place.
    **/
   [DBus (name="org.wrowclif.GmailNotify.Hub")]
   public interface DbusHubInterface : Object {

      public static const string BUS_NAME    =  "org.wrowclif.GmailNotify.Hub";
      public static const string OBJECT_PATH = "/org/wrowclif/GmailNotify/Hub";

      public abstract void register_instance(InstanceInfo instance) throws IOError;

      public abstract void get_instance_list(out InstanceInfo[] instances) throws IOError;

      public signal void instance_added(InstanceInfo newInstance);
   }

   /**
    * Information about a specific email message
    **/
   public struct MessageInfo {
      string author;
      string subject;
      string summary;
   }

   /**
    * Information about a specific gmailnotify instance
    **/
   public struct InstanceInfo {
      int instanceId;
      string busName;
   }

}
