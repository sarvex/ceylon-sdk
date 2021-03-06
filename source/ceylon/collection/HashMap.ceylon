import ceylon.collection {
    Cell,
    entryStore,
    MutableMap
}

"A [[MutableMap]] implemented as a hash map stored in an 
 [[Array]] of singly linked lists of [[Entry]]s. Each entry 
 is assigned an index of the array according to the hash 
 code of its key. The hash code of a key is defined by 
 [[Object.hash]].
 
 The [[stability]] of a `HashMap` controls its iteration
 order:
 
 - A [[linked]] map has a stable and meaningful order of 
   iteration. The entries of the map form a linked list, 
   where new entries are added to the end of the linked 
   list. Iteration of the map follows this linked list, from 
   least recently added elements to most recently added 
   elements.
 - An [[unlinked]] map has an unstable iteration order that 
   may change when the map is modified. The order itself is 
   not meaningful to a client.
 
 The management of the backing array is controlled by the
 given [[hashtable]]."

by ("Stéphane Épardaud")
shared class HashMap<Key, Item>
        (stability=linked, hashtable = Hashtable(), entries = {})
        satisfies MutableMap<Key, Item>
        given Key satisfies Object {
    
    "Determines whether this is a linked hash map with a
     stable iteration order."
    Stability stability;
    
    "The initial entries in the map."
    {<Key->Item>*} entries;
    
    "Performance-related settings for the backing array."
    Hashtable hashtable;
    
    // For Collections, we can efficiently obtain an 
    // accurate initial capacity. For a generic iterable,
    // just use the given initialCapacity.
    value accurateInitialCapacity 
            = entries is Collection<Anything>;
    Integer initialCapacity 
            = accurateInitialCapacity 
                    then hashtable.initialCapacityForSize(entries.size) 
                    else hashtable.initialCapacityForUnknownSize();
    
    "Array of linked lists where we store the elements.
     
     Each element is stored in a linked list from this array
     at the index of the hash code of the element, modulo the
     array size."
    variable value store = entryStore<Key,Item>(initialCapacity);

    "Number of elements in this map."
    variable Integer length = 0;
    
    "Head of the traversal linked list if in `linked` mode. 
     Storage is done in [[store]], but traversal is done 
     using an alternative linked list maintained to have a 
     stable iteration order. Note that the cells used are 
     the same as in the [[store]], except for storage we use 
     [[Cell.rest]] for traversal, while for the stable 
     iteration we use the [[LinkedCell.next]]/[[LinkedCell.previous]]
     attributes of the same cell."
    variable LinkedCell<Key->Item>? head = null;
    
    "Tip of the traversal linked list if in `linked` mode."
    variable LinkedCell<Key->Item>? tip = null;
    
    // Write
    
    function hashCode(Object key) {
        value h = key.hash;
        return h.xor(h.rightLogicalShift(16));
    }
    
    Integer storeIndex(Object key, Array<Cell<Key->Item>?> store)
            => hashCode(key).and(store.size-1);
    
    Cell<Key->Item> createCell(Key->Item entry, Cell<Key->Item>? rest) {
        Cell<Key->Item> result;
        if (stability==linked) {
            value cell = LinkedCell(entry, rest, tip);
            if (exists last = tip) {
                last.next = cell;
            }
            tip = cell;
            if (!head exists) {
                head = cell;
            }
            result = cell;
        }
        else {
            result = Cell(entry, rest);
        }
        //result.hashCode = entry.key.hash;
        return result;
    }
    
    void deleteCell(Cell<Key->Item> cell) {
        if (stability==linked) {
            assert (is LinkedCell<Key->Item> cell);
            if (exists last = cell.previous) {
                last.next = cell.next;
            }
            else {
                head = cell.next;
            }
            if (exists next = cell.next) {
                next.previous = cell.previous;
            }
            else {
                tip = cell.previous;
            }
        }
    }
    
    Boolean addToStore(Array<Cell<Key->Item>?> store, Key->Item entry) {
        Integer index = storeIndex(entry.key, store);
        variable value bucket = store.getFromFirst(index);
        while (exists cell = bucket) {
            if (cell.element.key == entry.key) {
                // modify an existing entry
                cell.element = entry;
                return false;
            }
            bucket = cell.rest;
        }
        // add a new entry
        store.set(index, createCell(entry, store.getFromFirst(index)));
        return true;
    }
    
    void checkRehash() {
        if (hashtable.rehash(length, store.size)) {
            // must rehash
            value newStore = entryStore<Key,Item>
                    (hashtable.capacity(length));
            variable Integer index = 0;
            // walk every bucket
            while (index < store.size) {
                variable value bucket = store.getFromFirst(index);
                while (exists cell = bucket) {
                    bucket = cell.rest;
                    Integer newIndex = storeIndex(cell.element.key, newStore);
                    value newBucket = newStore[newIndex];
                    cell.rest = newBucket;
                    newStore.set(newIndex, cell);
                }
                index++;
            }
            store = newStore;
        }
    }
    
    // Add initial values
    for (entry in entries) {   
        if (addToStore(store, entry)) {
            length++;
        }
    }
    // After collecting all the initial
    // values, rebuild the hashtable if
    // necessary
    if (!accurateInitialCapacity) {
        checkRehash();
    }
    
    // End of initialiser section
    
    shared actual Item? put(Key key, Item item) {
        Integer index = storeIndex(key, store);
        value entry = key->item;
        value headBucket = store.getFromFirst(index);
        variable value bucket = headBucket;
        while (exists cell = bucket) {
            if (cell.element.key == key) {
                Item oldItem = cell.element.item;
                // modify an existing entry
                cell.element = entry;
                return oldItem;
            }
            bucket = cell.rest;
        }
        // add a new entry
        store.set(index, createCell(entry, headBucket));
        length++;
        checkRehash();
        return null;
    }
    
    shared actual Boolean replaceEntry(Key key, 
        Item&Object item, Item newItem) {
        Integer index = storeIndex(key, store);
        variable value bucket = store.getFromFirst(index);
        while (exists cell = bucket) {
            if (cell.element.key == key) {
                if (exists oldItem = cell.element.item, 
                    oldItem==item) {
                    // modify an existing entry
                    cell.element = key->newItem;
                    return true;
                }
                else {
                    return false;
                }
            }
            bucket = cell.rest;
        }
        return false;
    }

    
    shared actual void putAll({<Key->Item>*} entries) {
        for (entry in entries) {
            if (addToStore(store, entry)) {
                length++;
            }
        }
        checkRehash();
    }
    
    shared actual Item? remove(Key key) {
        Integer index = storeIndex(key, store);
        if (exists head = store.getFromFirst(index), 
            head.element.key == key) {
            store.set(index,head.rest);
            deleteCell(head);
            length--;
            return head.element.item;
        }
        variable value bucket = store.getFromFirst(index);
        while (exists cell = bucket) {
            value rest = cell.rest;
            if (exists rest,
                rest.element.key == key) {
                cell.rest = rest.rest;
                deleteCell(rest);
                length--;
                return rest.element.item;
            }
            else {
                bucket = rest;
            }
        }
        return null;
    }
    
    shared actual Boolean removeEntry(Key key, Item&Object item) {
        Integer index = storeIndex(key, store);
        while (exists head = store.getFromFirst(index), 
            head.element.key == key) {
            if (exists it = head.element.item, it==item) {
                store.set(index,head.rest);
                length--;
                return true;
            }
            else {
                return false;
            }
        }
        variable value bucket = store.getFromFirst(index);
        while (exists cell = bucket) {
            value rest = cell.rest;
            if (exists rest,
                rest.element.key == key) {
                if (exists it = rest.element.item, it==item) {
                    cell.rest = rest.rest;
                    deleteCell(rest);
                    length--;
                    return true;
                }
                else {
                    return false;
                }
            }
            else {
                bucket = rest;
            }
        }
        return false;
    }
    
    shared actual void clear() {
        variable Integer index = 0;
        // walk every bucket
        while (index < store.size) {
            store.set(index++, null);
        }
        length = 0;
        head = null;
        tip = null;
    }
    
    // Read
    
    size => length;
    
    empty => length==0;
    
    shared actual Item? get(Object key) {
        if (empty) {
            return null;
        }
        Integer index = storeIndex(key, store);
        //Integer hashCode = key.hash;
        variable value bucket = store.getFromFirst(index);
        while (exists cell = bucket) {
            if (//cell.hashCode==hashCode && 
                cell.element.key == key) {
                return cell.element.item;
            }
            bucket = cell.rest;
        }
        return null;
    }
    
    shared actual <Key->Item>? first {
        if (stability==linked) {
            return head?.element;
        }
        else {
            return store[0]?.element;
        }
    }
    
    /*shared actual Collection<Item> values {
        value ret = LinkedList<Item>();
        variable Integer index = 0;
        // walk every bucket
        while (index < store.size) {
            variable value bucket = store.getFromFirst(index);
            while (exists cell = bucket) {
                ret.add(cell.element.item);
                bucket = cell.rest;
            }
            index++;
        }
        return ret;
    }
    
    shared actual Set<Key> keys {
        value ret = HashSet<Key>();
        variable Integer index = 0;
        // walk every bucket
        while (index < store.size) {
            variable value bucket = store.getFromFirst(index);
            while (exists cell = bucket) {
                ret.add(cell.element.key);
                bucket = cell.rest;
            }
            index++;
        }
        return ret;
    }
    
    shared actual Map<Item,Set<Key>> inverse {
        value ret = HashMap<Item,MutableSet<Key>>();
        variable Integer index = 0;
        // walk every bucket
        while (index < store.size) {
            variable value bucket = store.getFromFirst(index);
            while (exists cell = bucket) {
                if (exists keys = ret[cell.element.item]) {
                    keys.add(cell.element.key);
                }else{
                    value k = HashSet<Key>();
                    ret.put(cell.element.item, k);
                    k.add(cell.element.key);
                }
                bucket = cell.rest;
            }
            index++;
        }
        return ret;
    }*/
    
    iterator() => stability==linked 
            then LinkedCellIterator(head)
            else StoreIterator(store);
    
    shared actual Integer count(Boolean selecting(Key->Item element)) {
        variable Integer index = 0;
        variable Integer count = 0;
        // walk every bucket
        while (index < store.size) {
            variable value bucket = store.getFromFirst(index);
            while (exists cell = bucket) {
                if (selecting(cell.element)) {
                    count++;
                }
                bucket = cell.rest;
            }
            index++;
        }
        return count;
    }
    
    shared actual void each(void step(Key->Item element)) {
        store.each(void (bucket) {
            variable value iter = bucket;
            while (exists cell = iter) {
                step(cell.element);
                iter = cell.rest;
            }
        });
    }
    
    shared actual Integer hash {
        variable Integer index = 0;
        variable Integer hash = 0;
        // walk every bucket
        while (index < store.size) {
            variable value bucket = store.getFromFirst(index);
            while (exists cell = bucket) {
                hash += cell.element.hash;
                bucket = cell.rest;
            }
            index++;
        }
        return hash;
    }
    
    shared actual Boolean equals(Object that) {
        if (is Map<Object,Anything> that,
            size == that.size) {
            variable Integer index = 0;
            // walk every bucket
            while (index < store.size) {
                variable value bucket = store.getFromFirst(index);
                while (exists cell = bucket) {
                    value thatItem = that[cell.element.key];
                    if (exists thisItem = cell.element.item) {
                        if (exists thatItem) {
                            if (thatItem!=thisItem) {
                                return false;
                            }
                        }
                        else {
                            return false;
                        }
                    }
                    else if (thatItem exists) {
                        return false;
                    }
                    bucket = cell.rest;
                }
                index++;
            }
            return true;
        }
        return false;
    }
    
    shared actual MutableMap<Key,Item> clone() {
        value clone = HashMap<Key,Item>(stability);
        if (stability==unlinked) {
            clone.length = length;
            clone.store = entryStore<Key,Item>(store.size);
            variable Integer index = 0;
            // walk every bucket
            while (index < store.size) {
                if (exists bucket = store.getFromFirst(index)) {
                    clone.store.set(index, bucket.clone()); 
                }
                index++;
            }
        }
        else {
            for (entry in this) {
                clone.put(entry.key, entry.item);
            }
        }
        return clone;
    }
    
    shared actual Boolean defines(Object key) {
        if (empty) {
            return false;
        }
        else {
            Integer index = storeIndex(key, store);
            variable value bucket = store.getFromFirst(index);
            while (exists cell = bucket) {
                if (cell.element.key == key) {
                    return true;
                }
                bucket = cell.rest;
            }
            return false;
        }
    }
    
    shared actual Boolean contains(Object entry) {
        if (empty) {
            return false;
        }
        else if (is Object->Anything entry) {
            value key = entry.key;
            Integer index = storeIndex(key, store);
            variable value bucket = store.getFromFirst(index);
            while (exists cell = bucket) {
                if (cell.element.key == key) {
                    if (exists item = cell.element.item) {
                        if (exists elementItem = entry.item) {
                            return item == elementItem;
                        }
                        else {
                            return false;
                        }
                    }
                    else {
                        return !entry.item exists;
                    }
                }
                bucket = cell.rest;
            }
            return false;
        }
        else {
            return false;
        }
    }
    
}
