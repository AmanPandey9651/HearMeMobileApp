import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/app_config.dart';
import '../../core/app_controller.dart';
import '../../widgets/backend_selector_sheet.dart';
import '../../widgets/common_widgets.dart';
import 'notifications_screen.dart';
import 'safety_support_screen.dart';
import 'how_it_works_screen.dart';

class AccountMenuScreen extends StatelessWidget{
  final Widget? profilePage;
  const AccountMenuScreen({super.key,this.profilePage});
  @override Widget build(BuildContext context){final app=context.watch<AppController>();return ListView(padding:const EdgeInsets.all(16),children:[
    ListTile(leading:const CircleAvatar(child:Icon(Icons.person)),title:Text(app.user?.fullName.isNotEmpty==true?app.user!.fullName:'Anonymous user'),subtitle:Text('${app.user?.email??''}\n${app.user?.isListener == true ? 'LISTENER' : (app.user?.role ?? '')}'),isThreeLine:true),const Divider(),
    if(profilePage!=null)ListTile(leading:const Icon(Icons.manage_accounts),title:const Text('Profile'),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>profilePage!))),
    ListTile(leading:const Icon(Icons.notifications_outlined),title:const Text('Notifications'),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const NotificationsScreen()))),
    ListTile(leading:const Icon(Icons.shield_outlined),title:const Text('Safety, blocked users & support'),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const SafetySupportScreen()))),
    ListTile(leading:const Icon(Icons.info_outline),title:const Text('How it works'),onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const HowItWorksScreen()))),
    ListTile(leading:const Icon(Icons.dns_outlined),title:const Text('Backend Server'),subtitle:Text('${AppConfig.currentEnvironment.displayName}\n${AppConfig.currentHost}',style:const TextStyle(fontSize:11)),isThreeLine:true,trailing:const Icon(Icons.tune,size:18),onTap:()=>showBackendSelectorSheet(context)),
    const Divider(),ListTile(leading:const Icon(Icons.logout,color:Colors.redAccent),title:const Text('Sign out'),onTap:()async{if(await confirm(context,'Sign out?','You will need to sign in again to use your account.'))await context.read<AppController>().logout();}),
  ]);}
}
