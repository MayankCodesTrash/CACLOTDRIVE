import Foundation
import CoreLocation

/// Sample routes that follow real streets, so the map shows actual roads.
/// The geometry was fetched once from the OSRM routing service, which uses OpenStreetMap data
/// (© OpenStreetMap contributors, ODbL: https://www.openstreetmap.org/copyright). The trips themselves are fictional.
/// Stored as Google-encoded polylines (precision 5), one per sample trip, in the same order as `SampleData`.
enum SampleRoutes {
    static let encoded: [String] = [
        #"yhp_G|o{zPdK@V@V?Z?~A?X?nA?jL?@?v@@|@?`J@zC?P?`@?AeD?_BCoFA{FAgE?_@AuBAsF?S?YEeO?[AcCAkCGuQF]@WCwLAwK?YAaF?G?U?W?[Fa_@?[?UByH?]?]?mAFmE@yC?W@W?qC@uB?E?kA@{A?cB?mA?w@?oB@[?W?[?aA@c@@gE?gAAuBCyA@mC@cA@_G?[?_@@iBAyG?eD?cB?W?Q?}@?g@?_C?U?S?UAy@?c@CsA@UB_@?g@?_B?[?m@?Q?UAmG?W?Y@sG?Y?{B@{A?mD?[?_@@yCD_E?YCkH?W?Y@{B@kB?_A@aB@yB?oA?c@?UAqC?c@EmB?u@CuICwDAiFD_@DUBG@CDGHETIT?z@Gl@Gr@Kj@KbAWd@OhA[hA[`AUh@KTEx@Kj@Cj@C`CCn@?nBAdDCP?R??c@?YAaAAi@Cm@Ec@Mg@Kc@GUGMQe@Y]OWMODEFIBCXUHC?g@@e@B_@"#,
        #"}`k_GhjvzP@hHBfU?vCCVGJGDU@q@@QFGPAb@?BeI@A`@?VAnAInDGp@K`@O^STURWLWFY@YCYIWQUUQ]M]G_@C_@Ag@Dc@LeAd@_ErBaKp@iDXcBPqAPsANwAL}ALeBFuAHaBBqB@iB?wBA_X@ob@AkY?kD@wE@kABwAH_BHoANwARyARkATgARw@^oA^eATq@FSv@eB^w@Zg@h@_Ab@y@xAkCd@_ATe@d@aAf@uAZ_Ab@}A^_BZ_ARqAToAPoAV{BT}BP_Cd@_HJ}A?M?]iHCoGGwD?kBAuB?eA@w@?a@Ae@Ca@EYESEk@Qc@Qc@Uk@_@e@a@e@e@U[c@k@Wa@[m@??Yq@Us@S{@q@{Cw@sDw@qDSu@K[?AIQKWMW]k@e@u@c@e@g@c@u@e@i@Uq@Ug@Im@Gc@Ac@?aFDoF@O??YAaAAi@Cm@Ec@Mg@Kc@GUGMQe@Y]OWMOOQwAsAq@k@iB}Ai@c@KK_@c@AAQWIMWe@Uq@Mc@Ic@Ik@Ci@ASAU?}CAgC?S?QAmDE}AA]Co@A{@?eA?wB@cF?I?U?]]KeB]qC[qAMI?OASCcCW_@?sBBC?K?[@Q@wAHy@F_A?}@Hy@CyBEeAMc@CYAYAg@?S?k@@W@S?S@oA@u@D_@BOFO?uA@aB?aCB_CBM?S?gB@_BBA?mA@sA@iFFuB@sA?U?[?Q?_NDuF?M?M?qD@{G?uF?O?S@cCBmEGeJBE?S??\@P?F?R?`@?j@?N@|A?`@?`@?\@n@@xD?NO?yA@[?gE@]?}A@wC@"#,
        #"mwn_GlotzP?V?TN?t@A^?P?^?R?H?R??gAAuBCyA@mC@cA@_G?[?_@@iBAyG?eD?cB?W?Q?}@?g@?_C?U?S?UAy@?c@CsA@UB_@?g@?_B?[?m@?Q?UAmG?W?Y@sG?Y?{B@{A?mD?[?_@@yCD_E?YCkH?W?Y@{B@kB?_A@aB@yB?oA?c@?UAqC?c@EmB?u@CuICwDAiFA_A?E?Q?]?O?w@CyH?{CKmC?S?U?iB?_C?U?OAqG?S?Q?QA}F?S?SAkG?]BS@IB[DuC?oA???W?Q@oD?cC?E?c@A]?_@C{BCiCA{@As@?_@Am@C}AAg@A_@?Y?u@?m@?}@?aA?m@?_@?G?u@?O?G?k@?y@?Q?O?_A?W?U?w@?oA?Q@qA?w@?kB?U?m@?[?g@?i@?O?g@?g@@yA?iA?y@@[?_B@cA?}@?o@?U@y@?c@?a@@C?u@?{A?i@@eA@qB?W@eB?wC?i@@cA@_A@oE?}A@K?qA?mA@cC?qD@eD?wC@}A?aA?oD@oG?kB@kH?wB?]@uA?o@?aB?qA?_A?oA?mD?uA?{L@}V?s@?c@A_HA_ACyK?uAA}EA{DGcMA}D?cDKsRVANALBNDNHLNLPJVDXDZB\@X?tBBh@@TDXFPHPJNLLNHPHNBN?zOD|JJfNF@m@CYQoAC_@A[?y@B[Ju@@K"#,
        #"whr_G`rtzPBu@DWBIJc@Nc@TSTBrANjDh@TDt@H`APf@JPDd@PRHj@Rf@RZTZXVZz@oAVi@Jm@lF?fBLfABnE??K?mC@mG?S?S?uFAgF?iF?g@DoC?OAa@?GCWC]Ky@Mw@Ia@k@aCKi@Gg@Em@Ak@@o@Bs@FqAFsAHyB?s@?q@As@Es@KeAQuAk@yD[aCKy@IaAE}@CqAAoAC_CCyB?]?U?G?_FIsB?W@kJDq@Fs@NcAReAZaA\y@\u@Vu@T{@Ns@Ly@Dm@Dm@@{@?wH?kDAkI?SAsM?mA?_GA}E?U?M?gA?Q?]A_F?S?S?uD?uEAyEFqE?kC?o@?_@@U?Y@YDmADqA?W?Y@cA?Y?aCA_C?S?S?qA?k@AQCg@EeAAIA]?YAeB?a@?cC?[?K@qC?mC?W?WAkC?eC?]?Y?qB@oD?U?S?eE?eE?O?_E@_L?iB?KB{P@{F@yBHeM?Q@SD{FBuD?_@BqEA_GGaFGqEAwBAaBByABkC?sA@sB@{D?q@?iC?a@?}C?gG?C?c@U?S?mB?sDCU?eC?eNAGAyM@gD?y@?Ce@AW?wAGg@?wA?AM[o@QcC_AByEAsGAsE}@Ac@]P]~@kCR[RSXMZCtB???"#,
        #"g|l_GxqozPD?R?J@T?R?L?N?p@AX?DAF@H@FBHB?D@D^p@DBF?F?FEFCDE@AB?BBJP@@BALOn@lAQTi@j@MJEJAJBRNh@FX@F?D?T{EAoF@aG?M?O?sD@oA@k@?aA?cEDu@?i@?W@A?kA?u@?o@?I?sB@_@?uB@Y?W?cA?M?U??b@?bAEpK?|B?X?V?lH?L?HA~D?FAnC?\A\AfK?X?nG?\?V@nG?R?P?fAB`BBj@Dp@BrA?b@@x@?T?RO?O@S?]?_A@}A@C?U@sA@_D@O?O?{A@S?U@e@?K?_@@]?K?K?k@@S?e@BG@EDKTs@bBy@pBELAJyAAwEC]AyB?m@?wD?wAA[?{FAAR?DA^Ad@En@In@Kh@C\A`@ARBt@Hd@H^N^RZ\\d@^\ZJTJ\DZ@\?VAdC?rB?P?jA"#,
        #"}ys_GphbzPq@?kOA{F@cCEwCQyFYyDWqKq@wMs@sLs@uMq@yLu@sMs@_Mu@mIcAy@QaAWw@[kAq@oAaAqBeBwBiBs@YDhI@`D@vGJDJ?lBm@`DkApCcAtAa@tAMt@CtABzDFtP~@bP`AvNv@xLp@bNt@jO|@`G\|F\vCL`CFz{@JhMBx@?xI\~Nn@pNx@xAHjXtArEV`BFvBFzMj@bH@bHC~C?jLEbNIhNGdO?hDRdCb@pAb@r@Xv@b@t@h@n@n@fAxAdAzAbA`B\p@Tl@X`A\~ARhAZrBXfCf@hJBp@\lMJbDbAp\RjFt@`VNjELnGNlFL`E`@jMR~GD`BNjETpJ@VJdCFfBFxBFpBPjGT~HLvDJxCj@tRb@zNX`Kl@lSj@zQf@fQb@~MTfIJ`DTfIPrFPzFf@|PHjCPtFBbB?tAA`AC~@GdAInAKlAMnAQdAUjAWhAe@dB[|@e@pA_@v@_AjBwAnCcAbBo@bAe@dAk@vAO\GPc@rAUr@Sp@Or@WjASnAStAOzAKtAG|AExAAjA?xE?jD?lY?lb@?fM?nLAdCC~AGxAGjAEv@KnAMtAQ|AOjAStAY`Bo@bDwBhKmCzMqBxJcA`F"#,
        #"_dq_GpubzPnG|DLHAzD?pD@fJBhK@pDB|L?l@?b@?jG@|C?`@?|D@xD?fEDdF@`B@vBFpEF`F@~FCpE?^CtDEzFAR?PIdMAxBAzFCzP?J?hBA~K?~D?N?dE?dE?R?TAnD?pB?XQ?u@@oC@O?M?wF@kF?M?M?iE@wA?gA?M?M?aB?}A@eC?O@yA?c@D_@L[L]PYTY\W^Wb@Wr@a@`BI\a@`BCHCHGLELUd@W`@c@d@[TULYL[J]D_@Bg@@A?O??Z?J?fF?P?T?`D?vE?jE?P?V?f@?p@?\?pA?~A?B?TS?uTJG?I?eC?iE?G?S?Q?{NDU@wCAG?iA@yAB_ABM@M@M??\@TBjL?TB`NHpNDnL?Z@hADtAHx@@fDAt@Gr@Kl@Md@[x@Ql@Kd@Ib@Eh@Aj@AV?LBjBB`P?P@ZA`G@tB?pF?V@jE?x@?rK?D@T?Z?PBfKDvN?j@@~F@`DHnBBvM?XArACz@KfAIp@QfAMd@CLYz@Wp@Yl@]l@]b@a@l@c@b@i@d@_@VQJ_@Ra@Na@Na@J[F[Dk@B{@@}HBQ?iMD}BAyA@kL?kA?uE@gG?qFB?vJ?R?bF?xC?xBQ|KExD?j@?fD?\@n@F`HDhF@xB?\AvB?vC?dB@jL@nA?n@?B@fA@~A?jABzEfFEhE@f@?jA@hGAfBA`DEzGCx@@V?"#,
        #"unj_G`wgzPcA?s@Aw@?u@@wBNoBJE@qDNq@Fd@pO@\b@vO`@nK\~GT`AT^^H|G??vBAtE?h@?~B?F?\i@?oAAe@MWMMI[]g@mAs@eD_AyEu@_E]wD_B}i@a@kMOuEOkFUsHCkK?}@?k@@m@Dq@Di@Fk@lBgOBSsDTgBJiBLyAJuAHU@kAHgBDy@?_B?u@A{@I{@Uw@_@{@k@{@y@g@o@i@cAa@cAmB}Fs@yBg@oAq@mAa@g@e@e@m@c@o@]ICIE_@Mo@Qc@Go@EcBAaGDoNH]?I?aDBgA?_DDG?_CBg@??c@A_HA_ACyK?uAA}EA{DGcMA}D?cDKsRG{JuACkAAQ?@hN?d@Kh@Qh@a@f@QLWJc@DmA?"#
    ]

    static func route(at index: Int) -> [RoutePoint] {
        decode(encoded[index % encoded.count])
    }

    /// Decodes a Google polyline (precision 5).
    static func decode(_ polyline: String) -> [RoutePoint] {
        let bytes = Array(polyline.utf8)
        var index = 0, lat = 0, lon = 0
        var points: [RoutePoint] = []

        func nextValue() -> Int? {
            var result = 0, shift = 0
            while index < bytes.count {
                let b = Int(bytes[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : (result >> 1) }
            }
            return nil
        }

        while index < bytes.count {
            guard let dLat = nextValue(), let dLon = nextValue() else { break }
            lat += dLat
            lon += dLon
            points.append(RoutePoint(lat: Double(lat) / 1e5, lon: Double(lon) / 1e5))
        }
        return points
    }

    /// Length of a route in meters.
    static func length(of points: [RoutePoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { total, pair in
            total + CLLocation(latitude: pair.0.lat, longitude: pair.0.lon)
                .distance(from: CLLocation(latitude: pair.1.lat, longitude: pair.1.lon))
        }
    }

    /// The point `distance` meters along the route, clamped to its ends.
    static func point(along points: [RoutePoint], at distance: Double) -> RoutePoint {
        guard var previous = points.first else { return RoutePoint(lat: 0, lon: 0) }
        var remaining = max(0, distance)
        for next in points.dropFirst() {
            let segment = CLLocation(latitude: previous.lat, longitude: previous.lon)
                .distance(from: CLLocation(latitude: next.lat, longitude: next.lon))
            if remaining <= segment, segment > 0 {
                let t = remaining / segment
                return RoutePoint(lat: previous.lat + (next.lat - previous.lat) * t, lon: previous.lon + (next.lon - previous.lon) * t)
            }
            remaining -= segment
            previous = next
        }
        return previous
    }
}
