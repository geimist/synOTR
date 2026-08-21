Ext.namespace("SYNO.SDS.synOTR.Utils");

Ext.define("SYNO.SDS.synOTR.Application", {
    extend: "SYNO.SDS.AppInstance",
    appWindowName: "SYNO.SDS.synOTR.MainWindow",
    constructor: function() {
        this.callParent(arguments);
    }
});

Ext.define("SYNO.SDS.synOTR.MainWindow", {
    extend: "SYNO.SDS.AppWindow",
    constructor: function(a) {
        this.appInstance = a.appInstance;
        SYNO.SDS.synOTR.MainWindow.superclass.constructor.call(this, Ext.apply({
            layout: "fit",
            resizable: true,
            cls: "syno-app-win",
            maximizable: true,
            minimizable: true,
            width: 1024,
            height: 700,
            html: SYNO.SDS.synOTR.Utils.getMainHtml()
        }, a));
        SYNO.SDS.synOTR.Utils.ApplicationWindow = this;
    },

    onOpen: function() {
        SYNO.SDS.synOTR.MainWindow.superclass.onOpen.apply(this, arguments);
    },

    onRequest: function(a) {
        SYNO.SDS.synOTR.MainWindow.superclass.onRequest.call(this, a);
    },

    onClose: function() {
        clearTimeout(SYNO.SDS.synOTR.TimeOutID);
        SYNO.SDS.synOTR.TimeOutID = undefined;
        SYNO.SDS.synOTR.MainWindow.superclass.onClose.apply(this, arguments);
        this.doClose();
        return true;
    }
});

Ext.apply(SYNO.SDS.synOTR.Utils, function() {
    return {
        getMainHtml: function() {
            // Timestamp must be inserted here to prevent caching of iFrame
            return '<iframe src="webman/3rdparty/synOTR/index.cgi?_ts=' + new Date().getTime() + '" title="synOTR" style="width: 100%; height: 100%; border: none; margin: 0"/>';
        }
    }
}());
