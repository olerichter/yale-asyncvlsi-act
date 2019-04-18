/*
  Structural Verilog to ACT file
*/
%type[X] {{ VWalk VRet }};

ver_file: module ver_file | module ;

module: "module" ID
{{X:
    module_t *m;

    NEW (m, module_t);
    m->next = NULL;
    A_INIT (m->conn);
    A_INIT (m->port_list);
    A_INIT (m->dangling_list);
    m->H = hash_new (128);
    m->b = hash_lookup ($0->M, $2);
    m->inst_exists = 0;
    m->flags = 0;
    m->hd = NULL;
    m->tl = NULL;
    if (m->b) {
      $E("Duplicate module name `%s'", $2);
    }
    m->b = hash_add ($0->M, $2);
    m->b->v = m;

    /* m is now the current module */
    q_ins ($0->hd, $0->tl, m);

    hash_bucket_t *x;
    x = hash_lookup ($0->missing, $2);
    if (x) {
      id_info_t *nm, *tmp;
      /* patching missing module links */
      nm = (id_info_t *)x->v;
      while (nm) {
	tmp = nm->nxt;
	nm->nxt = NULL;
	nm->m = m;
	update_id_info (nm);
	nm = tmp;
      }
    }
}}
"(" port_list ")" ";" module_body
;

port_list: { portname "," }* 
;

portname: id
{{X:
    $1->isport = 1;
    A_NEW (CURMOD($0)->port_list, id_info_t *);
    A_NEXT (CURMOD($0)->port_list) = $1;
    A_INC (CURMOD($0)->port_list);
    return NULL;
}}
| one_port
{{X:
    $1->isport = 1;
    A_NEW (CURMOD($0)->port_list, id_info_t *);
    A_NEXT (CURMOD($0)->port_list) = $1;
    A_INC (CURMOD($0)->port_list);
    return NULL;
}}
;

id[id_info_t *]: ID
{{X:
    id_info_t *id;
    char *tmp = NULL;

    if ($1[0] == '\\') {
      char buf[10240];
      MALLOC (tmp, char, strlen ($1));
      strcpy (tmp, $1+1);
      if ($0->a->mangle_string (tmp, buf, 10240) != 0) {
	$E("Act::mangle_string failed on string `%s'", $1);
      }
      FREE (tmp);
      id = gen_id ($0, buf);
    }
    else {
      id = gen_id ($0, $1);
    }
    return id;
}}
| STRING 
{{X:
    char buf[10240];
    id_info_t *id;

    if ($0->a->mangle_string ($1, buf, 10240) != 0) {
      $E("Act::mangle_string failed on string `%s'", $1);
    }
    id = gen_id ($0, buf);

    return id;
}}
;

module_body: decls 
{{X:
    int i;
    conn_info_t **c;
    conn_rhs_t *r;

    c = CURMOD($0)->conn;
    
    for (i=0; i < A_LEN (CURMOD($0)->conn); i++) {
      $A(c[i]->id.id->isport);
      if (c[i]->id.id->isinput || c[i]->id.id->isoutput) continue;
      if (c[i]->l) {
	r = (conn_rhs_t *) list_value (list_first (c[i]->l));
      }
      else {
	r = c[i]->r;
      }
      $A(r);
      if (r->id.id->isinput) {
	c[i]->id.id->isinput = 1;
      }
      else if (r->id.id->isoutput) {
	c[i]->id.id->isoutput = 1;
      }
      else {
	$W("Port name `%s' in module `%s': input/output direction unknown\n", c[i]->id.id->b->key, CURMOD($0)->b->key);
      }
    }
}}
assigns instances "endmodule" 
;

one_decl: decl_type [ "[" INT ":" INT "]" ] { id "," }**  ";"
{{X:
    listitem_t *li;
    int isarray;
    int lo, hi;
    VRet *r;
    id_info_t *id;
    int i;

    if (OPT_EMPTY ($2)) {
      isarray = 0;
    }
    else {
      r = LIST_VALUE(list_first ($2));
      $A(r->type == V_INT);
      lo = r->u.i;
      FREE (r);
      r = LIST_VALUE (list_next (list_first ($2)));
      $A(r->type == V_INT);
      hi = r->u.i;
      FREE (r);
      list_free ($2);
      if (lo > hi) {
	isarray = hi;
	hi = lo;
	lo = isarray;
      }
      isarray = 1;
    }
    for (li = list_first ($3); li; li = list_next (li)) {
      r = LIST_VALUE (li);
      $A(r->type == V_ID);
      id = r->u.id;
      FREE (r);

      if (A_LEN (id->a) > 0) {
	if (!((A_LEN (id->a) == 1 && isarray == 1))) {
	  $E("Identifier `%s' error in repeated array definition", id->b->key);
	}
	if (id->a[0].lo != lo || id->a[0].hi != hi) {
	  $E("Identifier `%s' dims don't match", id->b->key);
	}
	/* good, move on */
      }
      else {
	if (isarray) {
	  /* this id is an array! */
	  A_NEW (id->a, struct array_idx);
	  A_NEXT (id->a).lo = lo;
	  A_NEXT (id->a).hi = hi;
	  A_INC (id->a);
	}
      }
      /* now set to decl type */
      switch ($1) {
      case 0:
	id->isinput = 1;
	break;
      case 1:
	id->isoutput = 1;
	break;
      case 2:
	/* nothing */
	break;
      default:
	$E("Unknown decl type %d", $1);
	break;
      }
    }
    return NULL;
}}
;

decl_type[int]: "input" 
{{X: 
    return 0; 
}} 
| "output"
{{X:
    return 1;
}}
| "wire"
{{X:
    return 2;
}}
;

decls: one_decl decls | /* empty */ ;

assigns: one_assign assigns | /* empty */ ;

one_assign: "assign" id_deref "=" id_deref ";"
{{X:
    conn_rhs_t *r;
    conn_info_t *ci;

    NEW (r, conn_rhs_t);
    r->id = *($4);
    FREE ($4);
    r->issubrange = 0;

    NEW (ci, conn_info_t);

    A_NEW (CURMOD($0)->conn, conn_info_t *);
    A_NEXT (CURMOD ($0)->conn) = ci;
    A_INC (CURMOD ($0)->conn);
    
    ci->r = r;
    ci->l = NULL;
    ci->prefix = NULL;
    ci->id = *($2);
    ci->isclk = 0;
    FREE ($2);

    return NULL;
}}
;

instances: one_instance instances | /* empty */ ;

one_instance: id id 
{{X:
    hash_bucket_t *b;
    int i;

    q_ins ($0->tl->hd, $0->tl->tl, $2);

    $1->ismodname = 1;
    /* lookup id in the module table */
    b = hash_lookup ($0->M, $1->b->key);
    if (!b) {
      $2->m = NULL;
      /* external module */
      if (($2->p = v2act_find_lib ($0->a, $1->b->key))) {
	/* okay */
      }
      else {
	/* could be a module that appears later; add it to the
	   back-patch list */
	//$E("Reference to missing library module `%s'", $1->b->key);

	/* maybe this is later? */
	b = hash_lookup ($0->missing, $1->b->key);
	if (!b) {
	  b = hash_add ($0->missing, $1->b->key);
	  b->v = NULL;
	}
	$2->nxt = (id_info_t *)b->v;
	b->v = $2;
      }
      if ($2->p) {
	$2->nused = $2->p->getNumPorts();
      }
    }
    else {
      module_t *m;

      m = (module_t *)b->v;
      m->inst_exists = 1;
      $2->p = NULL;
      $2->m = m;
      $2->nused = A_LEN ($2->m->port_list);
    }
    /*
    MALLOC ($2->used, int, $2->nused);
    for (i=0; i < $2->nused; i++) {
      $2->used[i] = 0;
    }
    */
    update_id_info ($2);
    $2->isinst = 1;
    $2->nm = $1->b->key;
    $0->prefix = $2;
}}
"(" port_conns ")" ";"
{{X:
    update_conn_info ($2);
    $0->prefix = NULL;
    return NULL;
}}
 ;

port_conns: { one_port2 "," }* ;

one_port[id_info_t *]: "." id "(" id_or_const_or_array ")" 
{{X:
    int len;
    /* now add pending connections! id = blah */
    $4->id.id = $2;
    $4->id.isderef = 0;

    /* this is retarded */
    A_NEW (CURMOD($0)->conn, conn_info_t *);
    A_NEXT (CURMOD($0)->conn) = $4;
    A_INC (CURMOD($0)->conn);

    len = array_length ($4);
    if (len > 0) {
      /* excitement, this is an array, make sure the id is in fact an
	 array */
      if (A_LEN ($2->a) == 0) {
	A_NEW ($2->a, struct array_idx);
	A_NEXT ($2->a).lo = 0;
	A_NEXT ($2->a).hi = len-1;
	A_INC ($2->a);
      }
    }
    return $2;
}};

one_port2: "." id "(" id_or_const_or_array ")" 
{{X:
    /* THIS .id should not be part of the type table */

    /* emit connection! */
    $4->prefix = $0->prefix;
    $4->id.id = $2;
    $4->id.isderef = 0;
    A_NEW (CURMOD($0)->conn, conn_info_t *);
    A_NEXT (CURMOD($0)->conn) = $4;
    A_INC (CURMOD ($0)->conn);

    if ($0->prefix->p) {
      int k;
      /* check act process ports */

      k = $0->prefix->p->FindPort ($2->b->key);
      if (k != 0) {
	Assert (k > 0, "Hmm...");
	k--;
        $0->prefix->used[k] = 1;
      }
      else {
	$E("Connection to unknown port `%s'?", $2->b->key);
      }
    }
    else {
      int k;

      if ($0->prefix->m) {
	for (k=0; k < A_LEN ($0->prefix->m->port_list); k++) {
	  if (strcmp ($2->b->key, $0->prefix->m->port_list[k]->b->key) == 0) {
	    $0->prefix->used[k] = 1;
	    break;
	  }
	}
	if (k == A_LEN ($0->prefix->m->port_list)) {
	  $E("Connection to unknown port `%s'?", $2->b->key);
	}
      }
      else {
	/* punt */
	$0->prefix->mod = CURMOD ($0);
	if ($0->prefix->conn_start == -1) {
	  $0->prefix->conn_start = A_LEN (CURMOD ($0)->conn)-1;
	}
	$0->prefix->conn_end = A_LEN (CURMOD ($0)->conn)-1;
      }
    }
    return NULL;
}}
| "." id "(" ")" 
{{X:
    return NULL;
}};


id_deref[id_deref_t *]: id [ "[" INT "]" ]
{{X:
    id_deref_t *d;
    VRet *r;
    
    NEW (d, id_deref_t);
    d->id = $1;
    if (OPT_EMPTY ($2)) {
      d->isderef = 0;
    }
    else {
      d->isderef = 1;
      r = OPT_VALUE ($2);
      $A(r->type == V_INT);
      d->deref = r->u.i;
      FREE (r);
      list_free ($2);
    }
    return d;
}}
| /*INT*/ "1'b0"
{{X:
  id_deref_t *d;
  VRet *r;

  NEW (d, id_deref_t);
  d->id = gen_id ($0, "GND");
  d->isderef = 0;
  d->deref = 0;
  return d;
}}
| /*INT*/ "1'b1"
{{X:
  id_deref_t *d;
  VRet *r;

  NEW (d, id_deref_t);
  d->id = gen_id ($0, "Vdd");
  d->isderef = 0;
  d->deref = 0;
  return d;
}}
;

id_or_const[conn_rhs_t *]: id_deref [ "[" INT ":" INT "]" ]
{{X:
    conn_rhs_t *r;
    VRet *v;

    NEW (r, conn_rhs_t);

    r->id = *($1);
    FREE ($1);
    if (OPT_EMPTY ($2)) {
      r->issubrange = 0;
    }
    else {
      r->issubrange = 1;
      v = LIST_VALUE (list_first ($2));
      $A(v->type == V_INT);
      r->hi = v->u.i;
      FREE (v);
      v = LIST_VALUE (list_next (list_first ($2)));
      $A(v->type == V_INT);
      r->lo = v->u.i;
      FREE (v);
      if (r->hi < r->lo) {
	int tmp;
	tmp = r->lo;
	r->lo = r->hi;
	r->hi = tmp;
      }
    }
    return r;
}}
| INT
{{X:
    id_info_t *id;
    conn_rhs_t *r;

    if ($1) {
      id = gen_id ($0, "Vdd");
      id->isport = 1;
    }
    else {
      id = gen_id ($0, "GND");
      id->isport = 1;
    }
    NEW (r, conn_rhs_t);
    r->id.id = id;
    r->id.isderef = 0;
    r->issubrange = 0;

    return r;
}}
;

id_or_const_or_array[conn_info_t *]: id_or_const
{{X:
    conn_info_t *c;

    NEW (c, conn_info_t);
    c->prefix = NULL;
    c->id.id = NULL;
    c->id.isderef = 0;
    c->l = NULL;
    c->r = $1;
    c->isclk = 0;
    return c;
}}
| "{" { id_or_const "," }* "}"
{{X:
    conn_info_t *c;

    NEW (c, conn_info_t);
    c->prefix = NULL;
    c->id.id = NULL;
    c->id.isderef = 0;
    c->r = NULL;
    c->l = $2;
    c->isclk = 0;
    return c;
}}
;

