// ignore_for_file: implementation_imports

import 'dart:convert';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import 'package:isar/src/query_builder.dart';

class Service {
  static const kNormalTimeout = Duration(seconds: 4);
  static const kLongTimeout = Duration(seconds: 10);
  final VmService _service;
  final String _isolateId;

  Service._(this._service, this._isolateId);

  static Future<Service> connect(String uri) async {
    final vmService = await vmServiceConnectUri(uri);
    final vm = await vmService.getVM();
    final isolateId = vm.isolates!.where((e) => e.name == 'main').first.id!;
    print(isolateId);
    final service = Service._(vmService, isolateId);
    final version = await service.getVersion();
    await service._service.streamListen(EventStreams.kExtension);
    service._service.onExtensionEvent.listen((event) {
      print('HELLO');
    });
    if (version != 1) {
      throw 'Wrong version';
    }
    return service;
  }

  Future<T> _call<T>(String method,
      {Duration? timeout = kNormalTimeout, Map<String, dynamic>? args}) async {
    var responseFuture = _service.callServiceExtension('ext.isar.$method',
        isolateId: _isolateId, args: args);
    if (timeout != null) {
      responseFuture = responseFuture.timeout(timeout);
    }

    final response = await responseFuture;
    return response.json!['value'] as T;
  }

  Future<int> getVersion() => _call('getVersion');

  Future<List<dynamic>> getSchema() => _call('getSchema');

  Future<List<String>> listInstances() async {
    final instances = await _call('listInstances');
    return (instances as List).cast();
  }

  Future<List<Map<String, dynamic>>> executeQuery(
      String instance,
      String collection,
      QueryOperation filter,
      int offset,
      int limit,
      int? sortPropertyIndex,
      bool ascending) async {
    final args = serializeQuery(instance, collection, filter, offset, limit,
        sortPropertyIndex, ascending);
    final objects = await _call(
      'executeQuery',
      args: args,
      timeout: kLongTimeout,
    );
    return (objects as List).cast();
  }

  Future watchQuery(
      String instance, String collection, QueryOperation filter) async {
    final args =
        serializeQuery(instance, collection, filter, null, null, null, true);
    await _call(
      'watchQuery',
      args: args,
      timeout: kNormalTimeout,
    );
  }

  Map<String, dynamic> serializeQuery(
      String instance,
      String collection,
      QueryOperation filter,
      int? offset,
      int? limit,
      int? sortPropertyIndex,
      bool ascending) {
    return {
      'instance': instance,
      'collection': collection,
      if (offset != null) 'offset': offset,
      if (limit != null) 'limit': limit,
      if (sortPropertyIndex != null) ...{
        'sortPropertyIndex': sortPropertyIndex,
        'ascending': ascending,
      },
      'filter': jsonEncode(serializeFilter(filter)),
    };
  }

  Map<String, dynamic> serializeFilter(QueryOperation filter) {
    if (filter is QueryCondition) {
      return {
        'type': 'QueryCondition',
        'conditionType': filter.conditionType.index,
        'propertyIndex': filter.propertyIndex,
        'propertyType': filter.propertyType,
        'lower': filter.lower,
        'includeLower': filter.includeLower,
        'upper': filter.upper,
        'includeUpper': filter.includeUpper,
        'caseSensitive': filter.caseSensitive,
      };
    } else if (filter is FilterGroup) {
      return {
        'type': 'FilterGroup',
        'conditions': filter.conditions.map((e) => serializeFilter(e)).toList(),
        'groupType': filter.groupType!.index,
      };
    }
    throw 'unreachable';
  }

  Future get onDone => _service.onDone;
}