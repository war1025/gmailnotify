
namespace GmailFeed {

   [DBus (name="org.gnome.Shell.SearchProvider2")]
   public class GmailSearch : Object {

      public static const string BUS_NAME = "org.wrowclif.GmailSearch";
      public static const string OBJECT_PATH = "/org/wrowclif/GmailSearch";

      private Gee.Map<int, DbusInstanceInterface> instances;

      private DbusHubInterface? hub;

      public GmailSearch() {
         instances = new Gee.TreeMap<int, DbusInstanceInterface>();

         Idle.add(watch_hub);
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

            foreach(var instance in instances.values) {
               try {
                  int count;
                  instance.get_message_count(out count);

                  have_messages |= (count > 0);

                  if(have_messages) {
                     break;
                  }
               } catch(IOError io) {
                  stdout.printf("Error getting number of messages for instance.\n");
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
      public void get_subsearch_result_set(string[] previous,
                                           string[] terms,
                                  out string[] results) {
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

         foreach(var entry in instances.entries) {
            try {
               MessageInfo[] messages;
               var instance_id = "%d".printf(entry.key);
               entry.value.get_message_list(out messages);

               foreach(var message in messages) {
                  var meta = new HashTable<string, Variant>(str_hash, str_equal);

                  meta["id"] = instance_id;
                  meta["name"] = "%s : %s".printf(message.author, message.subject);
                  meta["description"] = message.summary;
                  meta["gicon"] = "fake";

                  message_list.add(meta);
               }
            } catch(IOError io) {
               stdout.printf("Error getting message list for instance.\n");
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
         int instance_id = int.parse(identifier);

         instances[instance_id].open_message_window();
      }

      /**
       * Launch happens when the user clicks the app icon to the left of the result.
       *
       * @param terms     The search terms
       * @param timestamp When the search happened
       **/
      public void launch_search(string[] terms, uint timestamp) {

      }

      private void register_instance(InstanceInfo newInstance) {
         stdout.printf("Registering instance: %s", newInstance.busName);
         Idle.add(() => {finish_register_instance(newInstance); return false;});
      }

      private void finish_register_instance(InstanceInfo instanceInfo) {
         if(instances.has_key(instanceInfo.instanceId)) {
            return;
         }
         DbusInstanceInterface instance;
         instance = Bus.get_proxy_sync(BusType.SESSION,
                                     instanceInfo.busName,
                                     DbusInstanceInterface.OBJECT_PATH);
         instances[instanceInfo.instanceId] = instance;

         uint watch_key = 0;
         watch_key = Bus.watch_name(BusType.SESSION,
                                    instanceInfo.busName,
                                    BusNameWatcherFlags.NONE,
                                    null,
                                    () => {
                                       instances.unset(instanceInfo.instanceId);
                                       Bus.unwatch_name(watch_key);
                                    });
      }

      private bool watch_hub() {
         Bus.watch_name(BusType.SESSION, DbusHubInterface.BUS_NAME, BusNameWatcherFlags.NONE,
                        (connection, name, owner) => {
                           hub = Bus.get_proxy_sync(BusType.SESSION,
                                                    DbusHubInterface.BUS_NAME,
                                                    DbusHubInterface.OBJECT_PATH);

                           hub.instance_added.connect(register_instance);

                           InstanceInfo[] currentInstances;
                           hub.get_instance_list(out currentInstances);

                           foreach(var instanceInfo in currentInstances) {
                              register_instance(instanceInfo);
                           }
                        });

         if(hub == null) {
            hub = Bus.get_proxy_sync(BusType.SESSION,
                                     DbusHubInterface.BUS_NAME,
                                     DbusHubInterface.OBJECT_PATH);
         }

         return false;
      }
   }
}

namespace GmailSearchProvider {
   void main(string[] args) {
      Bus.own_name(BusType.SESSION, GmailFeed.GmailSearch.BUS_NAME, BusNameOwnerFlags.NONE,
                   (c) => {
                      c.register_object(GmailFeed.GmailSearch.OBJECT_PATH,
                      new GmailFeed.GmailSearch());
                   },
                   () => {},
                   () => stderr.printf ("Could not aquire name\n"));

      new MainLoop().run();
   }
}
