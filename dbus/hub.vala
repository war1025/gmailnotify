
namespace GmailFeed {

   [DBus (name="org.wrowclif.GmailNotify.Hub")]
   public class DbusHub : Object {

      public signal void instance_added(InstanceInfo newInstance);

      private Gee.Map<int, DbusInstanceInterface> instances;
      private Gee.Map<int, string>                instanceInfos;

      public DbusHub() {
         instances     = new Gee.TreeMap<int, DbusInstanceInterface>();
         instanceInfos = new Gee.TreeMap<int, string>();
      }

      public void get_instance_list(out InstanceInfo[] instanceList) {
         instanceList = new InstanceInfo[instanceInfos.size];

         int i = 0;
         foreach(var entry in instanceInfos.entries) {
            instanceList[i] = {entry.key, entry.value};
            i++;
         }
      }

      public void register_instance(InstanceInfo instance) {
         Idle.add(() => {finish_register_instance(instance); return false;});
      }

      private void finish_register_instance(InstanceInfo instanceInfo) {
         if(instances.has_key(instanceInfo.instanceId)) {
            return;
         }
         DbusInstanceInterface instance;
         instance = Bus.get_proxy_sync(BusType.SESSION,
                                     instanceInfo.busName,
                                     DbusInstanceInterface.OBJECT_PATH);

         instances[instanceInfo.instanceId]     = instance;
         instanceInfos[instanceInfo.instanceId] = instanceInfo.busName;

         uint watch_key = 0;
         watch_key = Bus.watch_name(BusType.SESSION, instanceInfo.busName,
                                    BusNameWatcherFlags.NONE,
                                    null,
                                    () => {
                                       instances.unset(instanceInfo.instanceId);
                                       instanceInfos.unset(instanceInfo.instanceId);
                                       Bus.unwatch_name(watch_key);
                                    });

         instance_added(instanceInfo);
      }
   }

}

namespace GmailDbusHub {
   void main(string[] args) {
      Bus.own_name(BusType.SESSION, GmailFeed.DbusHubInterface.BUS_NAME, BusNameOwnerFlags.NONE,
               (c) => {
                  c.register_object(GmailFeed.DbusHubInterface.OBJECT_PATH,
                  new GmailFeed.DbusHub());
               },
               () => {},
               () => stderr.printf ("Could not aquire name\n"));

      new MainLoop().run();
   }
}
