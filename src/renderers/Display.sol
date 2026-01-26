// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @dev Display — Solady helpers for on-chain SVG / string rendering:
library Display {
    /*──────────────────────  DATA URIs  ─────────────────────*/

    function jsonDataURI(string memory raw) internal pure returns (string memory) {
        return string.concat("data:application/json;base64,", encode(bytes(raw)));
    }

    function svgDataURI(string memory raw) internal pure returns (string memory) {
        return string.concat("data:image/svg+xml;base64,", encode(bytes(raw)));
    }

    function jsonImage(string memory name_, string memory description_, string memory svg_)
        internal
        pure
        returns (string memory)
    {
        return jsonDataURI(
            string.concat(
                '{"name":"',
                name_,
                '","description":"',
                description_,
                '","image":"',
                svgDataURI(svg_),
                '"}'
            )
        );
    }

    /*──────────────────────  SVG BASE  ─────────────────────*/

    function svgCardBase() internal pure returns (string memory) {
        return string.concat(
            "<svg xmlns='http://www.w3.org/2000/svg' width='420' height='600'>",
            "<defs><style>",
            ".g{font-family:'EB Garamond',serif;}",
            ".gb{font-family:'EB Garamond',serif;font-weight:600;}",
            ".m{font-family:'Courier Prime',monospace;}",
            "</style></defs>",
            "<rect width='420' height='600' fill='#000'/>",
            "<rect x='20' y='20' width='380' height='560' fill='none' stroke='#fff' stroke-width='1'/>"
        );
    }

    function svgHeader(string memory orgNameEsc, string memory subtitle)
        internal
        pure
        returns (string memory svg)
    {
        svg = string.concat(
            svgCardBase(),
            "<text x='210' y='55' class='gb' font-size='18' fill='#fff' text-anchor='middle' letter-spacing='3'>",
            orgNameEsc,
            "</text>",
            "<text x='210' y='75' class='g' font-size='11' fill='#fff' text-anchor='middle' letter-spacing='2'>",
            subtitle,
            "</text>",
            "<line x1='40' y1='90' x2='380' y2='90' stroke='#fff' stroke-width='1'/>"
        );
    }

    /*──────────────────────  DECIMAL IDs  ─────────────────────*/

    /// @dev "1234...5678" from a big decimal id:
    function shortDec4(uint256 v) internal pure returns (string memory) {
        string memory s = toString(v);
        uint256 n = bytes(s).length;
        if (n <= 11) return s;
        unchecked {
            return string.concat(slice(s, 0, 4), "...", slice(s, n - 4, n));
        }
    }

    /*──────────────────────  ADDRESSES  ─────────────────────*/

    /// @dev EIP-55 "0xAbCd...1234" (0x + 4 nibbles ... 4 nibbles):
    function shortAddr4(address a) internal pure returns (string memory) {
        string memory full = toHexStringChecksummed(a);
        uint256 n = bytes(full).length;
        unchecked {
            return string.concat(slice(full, 0, 6), "...", slice(full, n - 4, n));
        }
    }

    /*──────────────────────  NUMBERS  ─────────────────────*/

    /// @dev Decimal with commas: 123_456_789 => "123,456,789":
    function fmtComma(uint256 n) internal pure returns (string memory) {
        if (n == 0) return "0";
        uint256 temp = n;
        uint256 digits;
        while (temp != 0) {
            unchecked {
                ++digits;
                temp /= 10;
            }
        }
        uint256 commas = (digits - 1) / 3;
        bytes memory buf = new bytes(digits + commas);
        uint256 i = buf.length;
        uint256 dcount;
        while (n != 0) {
            if (dcount != 0 && dcount % 3 == 0) {
                unchecked {
                    buf[--i] = ",";
                }
            }
            unchecked {
                buf[--i] = bytes1(uint8(48 + (n % 10)));
                n /= 10;
                ++dcount;
            }
        }
        return string(buf);
    }

    /// @dev Format a 1e18-scaled token amount, with a simple "<1" for sub-unit values:
    function fmtAmount18Simple(uint256 amount) internal pure returns (string memory) {
        if (amount == 0) return "0";
        uint256 whole = amount / 1e18;
        if (whole == 0) return "&lt;1";
        return fmtComma(whole);
    }

    /// @dev Percent with 2 decimals from a/b, e.g. 1234/10000 => "12.34%":
    function percent2(uint256 a, uint256 b) internal pure returns (string memory) {
        if (b == 0) return "0.00%";
        uint256 p = (a * 10000) / b; // basis points
        uint256 whole = p / 100;
        uint256 frac = p % 100;
        return string.concat(toString(whole), ".", (frac < 10) ? "0" : "", toString(frac), "%");
    }

    /*──────────────────────  ESCAPE  ─────────────────────*/

    function esc(string memory s) internal pure returns (string memory result) {
        assembly ("memory-safe") {
            result := mload(0x40)
            let end := add(s, mload(s))
            let o := add(result, 0x20)
            mstore(0x1f, 0x900094)
            mstore(0x08, 0xc0000000a6ab)
            mstore(0x00, shl(64, 0x2671756f743b26616d703b262333393b266c743b2667743b))
            for {} iszero(eq(s, end)) {} {
                s := add(s, 1)
                let c := and(mload(s), 0xff)
                if iszero(and(shl(c, 1), 0x500000c400000000)) {
                    mstore8(o, c)
                    o := add(o, 1)
                    continue
                }
                let t := shr(248, mload(c))
                mstore(o, mload(and(t, 0x1f)))
                o := add(o, shr(5, t))
            }
            mstore(o, 0)
            mstore(result, sub(o, add(result, 0x20)))
            mstore(0x40, add(o, 0x20))
        }
    }

    /*──────────────────────  MINI STRING PRIMS  ─────────────────────*/

    function toString(uint256 value) internal pure returns (string memory result) {
        assembly ("memory-safe") {
            result := add(mload(0x40), 0x80)
            mstore(0x40, add(result, 0x20))
            mstore(result, 0)
            let end := result
            let w := not(0)
            for { let temp := value } 1 {} {
                result := add(result, w)
                mstore8(result, add(48, mod(temp, 10)))
                temp := div(temp, 10)
                if iszero(temp) { break }
            }
            let n := sub(end, result)
            result := sub(result, 0x20)
            mstore(result, n)
        }
    }

    function slice(string memory subject, uint256 start, uint256 end)
        internal
        pure
        returns (string memory result)
    {
        assembly ("memory-safe") {
            let l := mload(subject)
            if iszero(gt(l, end)) { end := l }
            if iszero(gt(l, start)) { start := l }
            if lt(start, end) {
                result := mload(0x40)
                let n := sub(end, start)
                let i := add(subject, start)
                let w := not(0x1f)
                for { let j := and(add(n, 0x1f), w) } 1 {} {
                    mstore(add(result, j), mload(add(i, j)))
                    j := add(j, w)
                    if iszero(j) { break }
                }
                let o := add(add(result, 0x20), n)
                mstore(o, 0)
                mstore(0x40, add(o, 0x20))
                mstore(result, n)
            }
        }
    }

    /*──────────────────────  MINI HEX PRIMS  ─────────────────────*/

    function toHexStringChecksummed(address value) internal pure returns (string memory result) {
        assembly ("memory-safe") {
            result := mload(0x40)
            mstore(0x40, add(result, 0x80))
            mstore(0x0f, 0x30313233343536373839616263646566)
            result := add(result, 2)
            mstore(result, 40)
            let o := add(result, 0x20)
            mstore(add(o, 40), 0)
            value := shl(96, value)
            for { let i := 0 } 1 {} {
                let p := add(o, add(i, i))
                let temp := byte(i, value)
                mstore8(add(p, 1), mload(and(temp, 15)))
                mstore8(p, mload(shr(4, temp)))
                i := add(i, 1)
                if eq(i, 20) { break }
            }
            mstore(result, 0x3078)
            result := sub(result, 2)
            mstore(result, 42)
            let mask := shl(6, div(not(0), 255))
            o := add(result, 0x22)
            let hashed := and(keccak256(o, 40), mul(34, mask))
            let t := shl(240, 136)
            for { let i := 0 } 1 {} {
                mstore(add(i, i), mul(t, byte(i, hashed)))
                i := add(i, 1)
                if eq(i, 20) { break }
            }
            mstore(o, xor(mload(o), shr(1, and(mload(0x00), and(mload(o), mask)))))
            o := add(o, 0x20)
            mstore(o, xor(mload(o), shr(1, and(mload(0x20), and(mload(o), mask)))))
        }
    }

    /*──────────────────────  MINI BASE64  ─────────────────────*/

    function encode(bytes memory data) internal pure returns (string memory result) {
        assembly ("memory-safe") {
            let dataLength := mload(data)
            if dataLength {
                let encodedLength := shl(2, div(add(dataLength, 2), 3))
                result := mload(0x40)
                mstore(0x1f, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef")
                mstore(0x3f, "ghijklmnopqrstuvwxyz0123456789+/")
                let ptr := add(result, 0x20)
                let end := add(ptr, encodedLength)
                let dataEnd := add(add(0x20, data), dataLength)
                let dataEndValue := mload(dataEnd)
                mstore(dataEnd, 0x00)
                for {} 1 {} {
                    data := add(data, 3)
                    let input := mload(data)
                    mstore8(0, mload(and(shr(18, input), 0x3F)))
                    mstore8(1, mload(and(shr(12, input), 0x3F)))
                    mstore8(2, mload(and(shr(6, input), 0x3F)))
                    mstore8(3, mload(and(input, 0x3F)))
                    mstore(ptr, mload(0x00))
                    ptr := add(ptr, 4)
                    if iszero(lt(ptr, end)) { break }
                }
                mstore(dataEnd, dataEndValue)
                mstore(0x40, add(end, 0x20))
                let o := div(2, mod(dataLength, 3))
                mstore(sub(ptr, o), shl(240, 0x3d3d))
                mstore(ptr, 0)
                mstore(result, encodedLength)
            }
        }
    }
}
