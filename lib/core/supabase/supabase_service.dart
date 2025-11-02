import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/enum.dart';

class SupabaseService {
  static Future<CheckBoundRes> checkBound(String displayDeviceId) async {
    print('[SupabaseService] checkBound：调用');
    final supabase = Supabase.instance.client;
    final resp = await supabase.functions.invoke(
      'device_check_binding',
      body: {'device_id': displayDeviceId},
    );
    if (resp.status != 200) {
      print('[SupabaseService] checkBound：调用失败 ${resp.data}');
      throw Exception('[SupabaseService] checkBound：调用失败 ${resp.data}');
    }
    final data = resp.data as Map;
    final isOwner = (data['is_owner'] == true);
    final isBound = (data['is_bound'] == true);

    return isOwner
        ? CheckBoundRes.isOwner
        : ((isBound ? CheckBoundRes.isBound : CheckBoundRes.notBound));
  }
}
