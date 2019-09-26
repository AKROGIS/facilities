/*
* Copyright 2013 - GPL
* Iván Eixarch <ivan@sinanimodelucro.org>
* https://github.com/joker-x/Leaflet.geoCSV
*
* This program is free software; you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation; either version 2 of the License, or
* (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
* GNU General Public License for more details.
*
* You should have received a copy of the GNU General Public License
* along with this program; if not, write to the Free Software
* Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
* MA 02110-1301, USA.
*/

L.GeoCSV = L.GeoJSON.extend({

  //opciones por defecto
  options: {
    firstLineTitles: true,
    fieldSeparator: ',',
	  latitudeTitle: 'latitude', //Case sensitive, no mangling or space removal
	  longitudeTitle: 'longitude', //ditto
    titles: ['lat', 'lng', 'popup'], //ignored if firstLineTitles = true
  },

  initialize: function (csv, options) {
    this._propertiesNames = [];
    L.Util.setOptions (this, options);
    L.GeoJSON.prototype.initialize.call (this, csv, options);
  },

  addData: function (data) {
    if (typeof data === 'string') {
      var csv = this._dsv(this.options.fieldSeparator);
      var rows;
      if (this.options.firstLineTitles) {
        rows = csv.parse(data);
        // rows will be an array of objects
        this.options.titles = rows.columns;
      } else {
        rows = csv.parseRows(data);
        //rows will be an array of arrays
      }
      //convertimos los datos a geoJSON
      data = this._csv2json(rows);
    }
		return L.GeoJSON.prototype.addData.call (this, data);
  },

  _csv2json: function (rows) {
    function pointFeature(lat,lng,props) {
      return {
        type: "Feature",
        geometry: {
          type: "Point",
          coordinates: [lng,lat]
        },
        properties: props
      };
    }
    var json = {
      type: "FeatureCollection"
    };
    if (this.options.firstLineTitles) {
      json["features"] = rows.map(element => {
        var lat = element[this.options.latitudeTitle];
        var lon = element[this.options.longitudeTitle];
        // TODO return null if lat/lon is invalid
        props = Object.assign({}, element);
        delete props[this.options.latitudeTitle];
        delete props[this.options.longitudeTitle];
        return pointFeature(lat,lon,props);
      });
    } else {
      var ilat = this.options.titles.indexof(this.options.latitudeTitle);
      var ilon = this.options.titles.indexof(this.options.longitudeTitle);
      json["features"] = rows.map(element => {
        var lat = element[ilat];
        var lon = element[ilon];
        // TODO return null if lat/lon is invalid
        props = {}
        element.array.forEach(element, i => {
          if (i != ilat || i != ilon) {
            props[this.options.titles[i]] = element
          }
        });
        return pointFeature(lat,lng,propos);
      });
    }
    return json;
  },

  _dsv: function(delimiter) {
    var reFormat = new RegExp("[\"" + delimiter + "\n\r]"),
        DELIMITER = delimiter.charCodeAt(0),
        EOL = {},
        EOF = {},
        QUOTE = 34,
        NEWLINE = 10,
        RETURN = 13;

    function _objectConverter(columns) {
      return new Function("d", "return {" + columns.map(function(name, i) {
        return JSON.stringify(name) + ": d[" + i + "] || \"\"";
      }).join(",") + "}");
    }

    function _customConverter(columns, f) {
      var object = _objectConverter(columns);
      return function(row, i) {
        return f(object(row), i, columns);
      };
    }

    function parse(text, f) {
      var convert, columns, rows = parseRows(text, function(row, i) {
        if (convert) return convert(row, i - 1);
        columns = row, convert = f ? _customConverter(row, f) : _objectConverter(row);
      });
      rows.columns = columns || [];
      return rows;
    }

    function parseRows(text, f) {
      var rows = [], // output rows
          N = text.length,
          I = 0, // current character index
          n = 0, // current line number
          t, // current token
          eof = N <= 0, // current token followed by EOF?
          eol = false; // current token followed by EOL?

      // Strip the trailing newline.
      if (text.charCodeAt(N - 1) === NEWLINE) --N;
      if (text.charCodeAt(N - 1) === RETURN) --N;

      function token() {
        if (eof) return EOF;
        if (eol) return eol = false, EOL;

        // Unescape quotes.
        var i, j = I, c;
        if (text.charCodeAt(j) === QUOTE) {
          while (I++ < N && text.charCodeAt(I) !== QUOTE || text.charCodeAt(++I) === QUOTE);
          if ((i = I) >= N) eof = true;
          else if ((c = text.charCodeAt(I++)) === NEWLINE) eol = true;
          else if (c === RETURN) { eol = true; if (text.charCodeAt(I) === NEWLINE) ++I; }
          return text.slice(j + 1, i - 1).replace(/""/g, "\"");
        }

        // Find next delimiter or newline.
        while (I < N) {
          if ((c = text.charCodeAt(i = I++)) === NEWLINE) eol = true;
          else if (c === RETURN) { eol = true; if (text.charCodeAt(I) === NEWLINE) ++I; }
          else if (c !== DELIMITER) continue;
          return text.slice(j, i);
        }

        // Return last token before EOF.
        return eof = true, text.slice(j, N);
      }

      while ((t = token()) !== EOF) {
        var row = [];
        while (t !== EOL && t !== EOF) row.push(t), t = token();
        if (f && (row = f(row, n++)) == null) continue;
        rows.push(row);
      }

      return rows;
    }

    return {
      parse: parse,
      parseRows: parseRows,
    };
  }

});

L.geoCsv = function (csv_string, options) {
  return new L.GeoCSV (csv_string, options);
};
