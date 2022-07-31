(() =>
{
    let fs = require("fs");
    let h = fs.openSync("\\\\.\\wacommunication", "w+");

    window.__wm_timer = null;
    window.__wm_chats = [];

    window.__wm_call = (method, data) =>
    {
        fs.writeSync(h, JSON.stringify({ method: method, data: data }));
        let b = Buffer.alloc(1024);
        fs.readSync(h, b, 0, 1024, 0);
        return JSON.parse(b.toString());
    };

    window.__wm_start = () => 
    {
        if (window.__wm_timer)
        {
            clearInterval(window.__wm_timer);
            window.__wm_timer = null;
        }

        let readStore = (store, start, func) => {
            return new Promise((resolve, reject) => {
                store.openCursor().onsuccess = event => {
                    let cursor = event.target.result;
                    if (cursor) {
                        func(start, cursor.value)
                        cursor.continue();
                    } else
                        return resolve(start);
                };
            });
        };

        load = () => {
            rq = window.indexedDB.open("model-storage");
            rq.onsuccess = async s => {
                let db = event.target.result;
                let t = db.transaction(["chat"]);

                let chats = await readStore(t.objectStore("chat"), [], (r, v) => r.push({id: v.id, muteExpiration: v.muteExpiration, unreadCount: v.unreadCount, lastCommunication: v.t}));
                let changedChats = chats.filter(c => !window.__wm_chats.some(cc => cc.id === c.id) || window.__wm_chats.some(cc => cc.id === c.id && (cc.muteExpiration != c.muteExpiration || cc.unreadCount != c.unreadCount || cc.lastCommunication != c.lastCommunication)));
                let removedChats = window.__wm_chats.filter(c => !chats.some(cc => cc.id === c.id));

                if (!changedChats.length && !removedChats.length)
                    return;

                window.__wm_chats = chats;

                t = db.transaction(["contact", "group-metadata"]);
                let contacts = await readStore(t.objectStore("contact"), {}, (r, v) => r[v.id.split('@')[0]] = v.name || v.pushName);
                let groups = await readStore(t.objectStore("group-metadata"), {}, (r, v) => r[v.id.split('@')[0]] = v.subject);
                let names = { ...contacts, ...groups };

                changedChats = changedChats.filter(c => names[c.id.split('@')[0]]);
                if (changedChats.length)
                    window.__wm_call("chat_list_update", changedChats.map(c => ({ ...c, name: names[c.id.split('@')[0]] })));

                if (removedChats.length)
                    window.__wm_call("chat_list_remove", removedChats.map(c => c.id));
            };
        };

        window.__wm_timer = setInterval(load, 1000);
    };

    window.__wm_stop = () =>
    {
        if (window.__wm_timer)
        {
            clearInterval(window.__wm_timer);
            window.__wm_timer = null;
        }

        if (window.__wm_chats.length)
        {
            window.__wm_chats = [];
            window.__wm_call("chat_list_clear", null);
        }
    };
})();