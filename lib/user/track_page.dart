// import 'package:flutter/material.dart';
// import 'package:flutter_map/flutter_map.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:custom_info_window/custom_info_window.dart';
// import 'package:day41/model/map_style.dart';
// import 'package:day41/pages/map_circles.dart';

// class Track extends StatelessWidget {
//   const Track({super.key});

//   @override
//    Widget build(BuildContext context) {
//     return Scaffold(
//       body: Stack(
//         children: [
//           GoogleMap(
//             myLocationButtonEnabled: false,
//             mapType: MapType.normal,
//             initialCameraPosition: _kGooglePlex,
//             zoomControlsEnabled: true,
//             markers: _markers.values.toSet(),
//             circles: circles.values.toSet(),
//             onTap: (LatLng latLng) {
//               _customInfoWindowController.hideInfoWindow!();
//               Marker marker = Marker(
//                 draggable: true,
//                 markerId: MarkerId(latLng.toString()),
//                 position: latLng,
//                 onTap: () {
//                   _customInfoWindowController.addInfoWindow!(
//                     Stack(
//                       children: [
//                         Container(
//                           padding: EdgeInsets.all(15.0),
//                           decoration: BoxDecoration(
//                             borderRadius: BorderRadius.circular(15.0),
//                             color: Colors.white,
//                           ),
//                           child: Column(
//                             crossAxisAlignment: CrossAxisAlignment.start,
//                             children: [
//                               Container(
//                                 width: double.infinity,
//                                 height: 130,
//                                 child: ClipRRect(
//                                   borderRadius: BorderRadius.circular(10.0),
//                                   child: Image.network(
//                                     'https://images.unsplash.com/photo-1606089397043-89c1758008e0?ixid=MnwxMjA3fDB8MHx0b3BpYy1mZWVkfDEyMHw2c01WalRMU2tlUXx8ZW58MHx8fHw%3D&ixlib=rb-1.2.1&auto=format&fit=crop&w=800&q=60',
//                                     fit: BoxFit.cover,
//                                   ),
//                                 ),
//                               ),
//                               SizedBox(height: 15,),
//                               Text("Grand Teton National Park", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14),),
//                               SizedBox(height: 5,),
//                               Text("Grand Teton National Park on the east side of the Teton Range is renowned for great hiking trails with stunning views of the Teton Range.", style: TextStyle(color: Colors.grey.shade600, fontSize: 12),),
//                               SizedBox(height: 8,),
//                               MaterialButton(
//                                 onPressed: () {},
//                                 elevation: 0,
//                                 height: 40,
//                                 minWidth: double.infinity,
//                                 color: Colors.grey.shade200,
//                                 shape: RoundedRectangleBorder(
//                                   borderRadius: BorderRadius.circular(10.0),
//                                 ),
//                                 child: Text("See details", style: TextStyle(color: Colors.black),),
//                               )
//                             ],
//                           ),
//                         ),
//                         Positioned(
//                           top: 5.0,
//                           left: 5.0,
//                           child: IconButton(
//                             icon: Icon(
//                               Icons.close,
//                               color: Colors.white,
//                             ),
//                             onPressed: () {
//                               _customInfoWindowController.hideInfoWindow!();
//                             },
//                           ),
//                         ),
//                       ],
//                     ),
//                     latLng,
//                   );
//                 },
//               );

//               setState(() {
//                 _markers[latLng.toString()] = marker;
//               });
//             },
//             onCameraMove: (position) {
//               _customInfoWindowController.onCameraMove!();
//             },
//             onMapCreated: (GoogleMapController controller) {
//               _controller = controller;
//               _customInfoWindowController.googleMapController = controller;
//             }
//           ),
//           CustomInfoWindow(
//             controller: _customInfoWindowController,
//             height: MediaQuery.of(context).size.height * 0.35,
//             width: MediaQuery.of(context).size.width * 0.8,
//             offset: 60.0,
//           ),
//           Positioned(
//             bottom: 40,
//             right: 15,
//             child: Container(
//               width: 35,
//               height: 105,
//               decoration: BoxDecoration(
//                 borderRadius: BorderRadius.circular(10),
//                 color: Colors.white
//               ),
//               child: Column(
//                 mainAxisAlignment: MainAxisAlignment.start,
//                 children: [
//                   MaterialButton(
//                     onPressed: () {
//                       _controller?.animateCamera(CameraUpdate.zoomIn());
//                     },
//                     padding: EdgeInsets.all(0),
//                     shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(10),
//                     ),
//                     child: Icon(Icons.add, size: 25),
//                   ),
//                   Divider(height: 5),
//                   MaterialButton(
//                     onPressed: () {
//                       _controller?.animateCamera(CameraUpdate.zoomOut());
//                     },
//                     padding: EdgeInsets.all(0),
//                     shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(10),
//                     ),
//                     child: Icon(Icons.remove, size: 25),
//                   )
//                 ],
//               )
//             ),
//           ),
//           Positioned(
//             bottom: 160,
//             right: 15,
//             child: Container(
//               width: 35,
//               height: 50,
//               decoration: BoxDecoration(
//                 borderRadius: BorderRadius.circular(10),
//                 color: Colors.white
//               ),
//               child: Column(
//                 mainAxisAlignment: MainAxisAlignment.start,
//                 children: [
//                   MaterialButton(
//                     onPressed: () {
//                       showModalBottomSheet(
//                         context: context,
//                         builder: (context) => Container(
//                           padding: EdgeInsets.all(20),
//                           color: Colors.white,
//                           height: MediaQuery.of(context).size.height * 0.3,
//                           child: Column(
//                             crossAxisAlignment: CrossAxisAlignment.start,
//                             children: [
//                               Text("Select Theme", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 18),),
//                               SizedBox(height: 20,),
//                               Container(
//                                 width: double.infinity,
//                                 height: 100,
//                                 child: ListView.builder(
//                                   scrollDirection: Axis.horizontal,
//                                   itemCount: _mapThemes.length,
//                                   itemBuilder: (context, index) {
//                                     return GestureDetector(
//                                       onTap: () {
//                                         _controller?.setMapStyle(_mapThemes[index]['style']);
//                                         Navigator.pop(context);
//                                       },
//                                       child: Container(
//                                         width: 100,
//                                         margin: EdgeInsets.only(right: 10),
//                                         decoration: BoxDecoration(
//                                           borderRadius: BorderRadius.circular(10),
//                                           image: DecorationImage(
//                                             fit: BoxFit.cover,
//                                             image: NetworkImage(_mapThemes[index]['image']),
//                                           )
//                                         ),
//                                       ),
//                                     );
//                                   }
//                                 ),
//                               ),
//                             ],
//                           )
//                         ),
//                       );
//                     },
//                     padding: EdgeInsets.all(0),
//                     shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(10),
//                     ),
//                     child: Icon(Icons.layers_rounded, size: 25),
//                   ),
//                 ],
//               )
//             ),
//           )
//         ],
//       ),
//     );
//   }
// }